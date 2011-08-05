class Admin::ReportsController < AdministrationController
  skip_before_filter :role_required

  def index
    @can_edit_reports = current_user.has_roles?(['administrator', 'agent'])
    @reports = get_reports_for_current_user
  end
  
  def run
	  @reports = get_reports_for_current_user
	  @menu = 'run_reports'
  end
  
  def new
    @report = Report.new
    init(@report)
  end

  def create
    @report = Report.new(params[:report])

    build_lists(@report)
	
    if @report.save
      flash[:success] = "Report was successfully created"
      redirect_to admin_reports_path
    else
      flash[:error] = "Problem in report creation"
      init(@report)
      render 'new'
    end
  end

  def edit
    @report = Report.find(params[:id])
    self.init(@report)
	
  end

  def update
    @report = Report.find(params[:id])

	  build_lists(@report)

    if @report.update_attributes(params[:report])
      flash[:success] = "Report was updated"
      redirect_to admin_reports_path
    else
      flash[:error] = "Problem in update"
      self.init(@report)
      render 'edit'
    end
  end
 
  def export
	  @report = Report.find(params[:id])
	  send_data(@report.export, :type => 'text/xml', :filename => "#{@report.name}.xml")
  end
  
  def import
  	begin
  		xml = params[:import_report].read
  		Report.import(xml)
  		flash[:success] = "Report was imported"
  		redirect_to admin_reports_path
  	rescue =>e
  		flash[:notice] = e.message.gsub('Validation failed: Name', 'Report').humanize
  		redirect_to admin_reports_path
  	end
  end
 
  def generate_utilization_report
    @menu = 'run_reports' if params[:return] == "run"
  end
  
  
  def display_utilization_report  
	  @menu = 'run_reports' if params[:return] == "run"
    
    start_date = Date.civil(params[:start_date][:year].to_i, params[:start_date][:month].to_i, params[:start_date][:day].to_i)
    end_date = Date.civil(params[:end_date][:year].to_i, params[:end_date][:month].to_i, params[:end_date][:day].to_i)
    #timespan =  Date.day_fraction_to_time(end_date - start_date)  # => [hours, minutes, seconds, ms]
    
    start_time = start_date.to_time.in_time_zone
    end_time = end_date.to_time.in_time_zone
        
    # Area.first.buildings.first.rooms.last.schedule
    # iterate areas, then buildings
    # then rooms then for each room call def available_and_booked_slots_for(start_time, end_time, has_agent_permission = false)
    
    @total_provisional_slots = @total_approved_slots = @total_available_slots = @total_maintenance_slots = 0
    @total_provisional_hours = @total_approved_hours = @total_available_hours = @total_maintenance_hours = 0
    @total_hours = 0
    
    Area.all.each do |area|
      area.buildings.each do |building|
        building.rooms.each do |room|
          total_minutes, provisional_slots, provisional_minutes, approved_slots, approved_minutes, available_minutes, available_slots, maintenance_minutes, maintenance_slots, total_slots =  room.report_available_and_booked_slots_for(start_time, end_time)
          
          #sanity check
          raise if (total_minutes != (provisional_minutes + approved_minutes + available_minutes + maintenance_minutes))
          
          @total_provisional_slots += provisional_slots
          @total_provisional_hours += (provisional_minutes/60)
          
          @total_approved_slots += approved_slots
          @total_approved_hours += (approved_minutes/60)
          
          @total_available_slots += available_slots
          @total_available_hours += (available_minutes/60)

          @total_maintenance_slots += maintenance_slots
          @total_maintenance_hours += (maintenance_minutes/60)
          
          @total_hours += (total_minutes/60)
          
          puts "@total_provisional_slots = #{@total_provisional_slots}"
          puts "@total_provisional_hours = #{@total_provisional_hours}"
          
          puts "@total_approved_slots = #{@total_approved_slots}"
          puts "@total_approved_hours = #{@total_approved_hours}"
          
          puts "@total_available_slots = #{@total_available_slots}"
          puts "@total_available_hours = #{@total_available_hours}"

          puts "@total_maintenance_slots = #{@total_maintenance_slots}"
          puts "@total_maintenance_hours = #{@total_maintenance_hours}"
        end
      end
    end    
  end
  
  def generate_report
    @reports = get_reports_for_current_user
	  @menu = 'run_reports' if params[:return] == "run"
	  @report = Report.find(params[:report][:id]) if params[:flow]
	
    # if params[:flow] == 'choose_report'
    #   @report = Report.find(params[:report][:id]) if params[:report][:id].present?
    # elsif params[:flow] == 'generate_report'
    #   @report = Report.find(params[:report][:id])
        
  	  if params[:commit] == 'Generate'	  
  		  file_name = "#{@report.name.gsub(" ", "-")}-reports-#{Time.zone.now.to_s(:number)}"
  		  @report.current_user = current_user
        @xml = @report.generate(params)
		
  		  if @xml.length > 0    
          case params[:download_format]
            when "XML"
              send_data(@xml, :type => 'text/xml', :filename => "#{file_name}.xml")
            when "XSLT"
              if @report.xslt_template.present? && !@report.xslt_template.data.blank?
                f = File.new("#{RAILS_ROOT}/tmp/#{file_name}.xml",  "w+")
                f1 = File.new("#{RAILS_ROOT}/tmp/#{file_name}.xsl",  "w+")
                f.write(@xml)
                f1.write(@report.xslt_template.data)
                f.close()
                f1.close()
                @output_xslt = `java -cp #{RAILS_ROOT}/lib XMLToHTMLThroXSLT #{RAILS_ROOT}/tmp/#{file_name}.xsl #{RAILS_ROOT}/tmp/#{file_name}.xml`
                RAILS_DEFAULT_LOGGER.debug "#{@output_xslt}"

                FileUtils.remove_file("#{RAILS_ROOT}/tmp/#{file_name}.xml", true)
                FileUtils.remove_file("#{RAILS_ROOT}/tmp/#{file_name}.xsl", true)
                render :action => 'print_report', :params => params
              else
                flash[:notice] = "Problem in XSLT Template"
              end
            when "XSL-FO"
              if @report.xslt_template.present? && !@report.xslt_template.xsl_fo.blank?
                f = File.new("#{RAILS_ROOT}/tmp/#{file_name}.xml",  "w+")
                f1 = File.new("#{RAILS_ROOT}/tmp/#{file_name}.xsl",  "w+")
                f.write(@xml)
                f1.write(@report.xslt_template.xsl_fo)
                f.close()
                f1.close()
                if Setting.app.fop.eql?('linux')
                  @output_xslt = `./lib/fop-1.0/fop -xml #{RAILS_ROOT}/tmp/#{file_name}.xml -xsl #{RAILS_ROOT}/tmp/#{file_name}.xsl -pdf #{RAILS_ROOT}/tmp/#{file_name}.pdf`
                elsif Setting.app.fop.eql?('windows')
                  @output_xslt = `#{RAILS_ROOT}/lib/fop-1.0/fop -xml #{RAILS_ROOT}/tmp/#{file_name}.xml -xsl #{RAILS_ROOT}/tmp/#{file_name}.xsl -pdf #{RAILS_ROOT}/tmp/#{file_name}.pdf`
                end
  			        puts "lib/fop-1.0/fop -xml #{RAILS_ROOT}/tmp/#{file_name}.xml -xsl #{RAILS_ROOT}/tmp/#{file_name}.xsl -pdf #{RAILS_ROOT}/tmp/#{file_name}.pdf"
			
                RAILS_DEFAULT_LOGGER.debug "#{@output_xslt}"

        				if @output_xslt.blank? && FileTest.exists?("#{RAILS_ROOT}/tmp/#{file_name}.pdf")
                  send_file("#{RAILS_ROOT}/tmp/#{file_name}.pdf")
                else
                  flash[:notice] = "Error in XSL-FO Template data"
                end
                FileUtils.remove_file("#{RAILS_ROOT}/tmp/#{file_name}.xml", true)
                FileUtils.remove_file("#{RAILS_ROOT}/tmp/#{file_name}.xsl", true)
                Delayed::Job.enqueue DelayedCleanupPdf.new(file_name), 0, 1.hour.from_now
              else
                flash[:notice] = "Error in XSL-FO Template data"
              end
            when "CSV"
              xml = @xml

              if (@report.csv_xslt_template&&@report.csv_xslt_template.data)
                f = File.new("#{RAILS_ROOT}/tmp/#{file_name}.xml",  "w+")
                f1 = File.new("#{RAILS_ROOT}/tmp/#{file_name}.xsl",  "w+")
                f.write(xml)
                f1.write(@report.csv_xslt_template.data)
                f.close()
                f1.close()
                if Setting.app.fop.eql?('linux')
                  @output_xslt = `./lib/fop-1.0/fop -xml #{RAILS_ROOT}/tmp/#{file_name}.xml -xsl #{RAILS_ROOT}/tmp/#{file_name}.xsl -foout #{RAILS_ROOT}/tmp/#{file_name}.out.xml`
                elsif Setting.app.fop.eql?('windows')
                  @output_xslt = `/lib/fop-1.0/fop -xml #{RAILS_ROOT}/tmp/#{file_name}.xml -xsl #{RAILS_ROOT}/tmp/#{file_name}.xsl -foout #{RAILS_ROOT}/tmp/#{file_name}.out.xml`
                end
                RAILS_DEFAULT_LOGGER.debug "#{@output_xslt}"

                xml = File.read("#{RAILS_ROOT}/tmp/#{file_name}.out.xml")

                FileUtils.remove_file("#{RAILS_ROOT}/tmp/#{file_name}.xml", true)
                FileUtils.remove_file("#{RAILS_ROOT}/tmp/#{file_name}.xsl", true)
                FileUtils.remove_file("#{RAILS_ROOT}/tmp/#{file_name}.out.xml", true)
              end

              outcsv = XmlToCsv.convert(xml)
              send_data(outcsv, :type => 'text/csv', :filename => "#{file_name}.csv")
            end
        else
          flash[:notice] = "No records found"
        end
      end
    # end
  end

  def destroy
    @report = Report.find(params[:id])
    if @report.destroy
      flash[:success] = "Report was successfully deleted"
      redirect_to admin_reports_path
    else
      flash[:notice] = "Problem in report deletion"
    end
  end

  def get_column_name
    params[:table_name] = 'user' if params[:table_name].eql?("booker") || params[:table_name].eql?("customer") 
    @column_list = params[:table_name].blank? ? [] : params[:table_name].singularize.camelize.constantize.column_names.dup
    render :update do |page|
      page.replace_html 'column_names', :partial => 'column_names'
    end
  end

  def get_af_fields
    params[:field_name] = 'customer_form' if params[:field_name].eql?('customer_details')
    @af_field_names = get_af_data
    render :update do |page|
      page.replace_html 'af_field_names', :partial => 'af_field_names'
    end
  end

  def get_af_param_fields
    params[:field_name] = 'customer_form' if params[:field_name].eql?('customer_details')
    @af_param_names = get_af_data
    render :update do |page|
      page.replace_html 'af_param_names', :partial => 'af_param_names'
    end
  end
  
  def get_af_data
    params[:field_name].blank? ? [] : current_app_setting.try("get_#{params[:field_name]}_fields".to_sym)
  end

  def get_associated_tables
    @table_names = params[:entity].blank? ? [] : Report.associated_tables(params[:entity])
    render :update do |page|
      page.replace_html 'table_names', :partial => 'table_names'
    end
  end

  protected

  def get_reports_for_current_user
    @reports = []
    if current_user.has_roles?('administrator')
      @reports = Report.all(:order => 'name')
    elsif current_user.has_roles?('agent')
      Report.all(:order => 'name').each do |r|
        @reports << r if (r.viewable_by.include?('anyone') || r.viewable_by.include?('agent') rescue false)
      end
    else
      Report.all(:order => 'name').each do |r|
        @reports << r if (r.viewable_by.include?('anyone') rescue false)
      end
    end
    @reports
  end
  
  def init(report)
  	@column_list = []
  	@table_names = []
    @af_field_names = []
  	@af_param_names = []
  	@table_names = Report.associated_tables(report.report_on) if report.report_on.present?
  end
  
  def build_lists(report)
	  report.build_list('list_of_fields', params[:table_name], params[:column_name])
    report.build_list('list_of_parameters', params[:param_type], params[:param_name])
    report.build_list('list_of_af_fields', params[:af_field_formname], params[:af_field_dataname])
	  report.build_list('list_of_af_parameters', params[:param_form], params[:param_field], params[:param_condition], params[:param_value])
  end
end
