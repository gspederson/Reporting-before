# == Schema Information
# Schema version: 20100913061020
#
# Table name: reports
#
#  id                    :integer(4)      not null, primary key
#  name                  :string(255)
#  sql                   :text
#  list_of_parameters    :text
#  created_at            :datetime
#  updated_at            :datetime
#  report_on             :string(255)
#  list_of_af_parameters :text
#  xslt_template_id      :integer(4)
#  list_of_fields        :text
#  viewable_by           :text
#
require 'rexml/document'

class Report < ActiveRecord::Base
  EntityName = %w(booking payment room customer supplier)
  AfSelectForms = %w(booking_form payment_form customer_details amount_details)
  AfParamForms = %w(booking_form payment_form customer_details)
  AFParamCondition = %w(matches does_not_match contains does_not_contain)
  ParamType = %w(start_date end_date text booking payment_method keyword keywords building room booking_category area customer supplier)
  CalculatedFields = %w(bookings_count sum_paid_bookings)
  
  belongs_to :xslt_template
  belongs_to :csv_xslt_template, :class_name=>'XsltTemplate'
  
  serialize :list_of_parameters, Array
  serialize :list_of_af_parameters, Array
  
  serialize :list_of_fields, Array
  serialize :list_of_af_fields, Array
  
  serialize :viewable_by, Array
  
  validates_presence_of :name
  validates_uniqueness_of :name, :case_sensitive => false, :message=>"already exists with this name"
  
  attr_accessor :current_user
  
  def build_list(field, first, second, third = nil, forth = nil)
    if !first.blank?
  	  unless (first.include?(""))
        newfield = first.zip(second)
        newfield = newfield.zip(third) unless third.nil?
        newfield = newfield.zip(forth) unless forth.nil?
  	  end
  	    newfield.collect!{|f| f.flatten}
    else
      newfield = nil
    end
	  self[field] = newfield
  end

	def self.associated_tables(table)
		my_tables = []
		case table
			when 'booking'
				my_tables = ['room','room_schema','booking_category','arrangement','booking_attendees','cancellation_reason','payments','events','booked_equipment','booked_supplier_items','supplier_item','building','sub_area','area','supplier', 'booker', 'customer', 'user', 'tags']
			when 'payment'
				my_tables = ['booking','events','room','room_schema','booking_category','arrangement','booking_attendees','cancellation_reason','booked_equipment','booked_supplier_items','supplier_item','building','sub_area','area','supplier', 'booker', 'customer', 'user', 'tags']
			when 'room'
				my_tables = ['bookings','events','room_schema','booking_category','arrangement','booking_attendees','cancellation_reason','booked_equipment','booked_supplier_items','supplier_item','building','sub_area','area','supplier', 'booker', 'customer', 'user', 'tags']
			when 'customer'
				my_tables = ['bookings','events','room_schema','booking_category','arrangements','booking_attendees','cancellation_reason','booked_equipment','booked_supplier_items','supplier_item','building','sub_area','area','supplier','booker', 'user', 'tags', 'rooms', 'payments']
			when 'supplier'
				my_tables = ['booking','room','room_schema','booking_category','arrangement','booking_attendees','cancellation_reason','payments','events','booked_equipment','booked_supplier_items','supplier_items','building','sub_area','area', 'booker', 'customer', 'user', 'tags']
			else
				#unknown table or nothing selected - return empty list
				return []
		end
		my_tables << table
		return my_tables.sort
	end

  def fields_in_hash(list)
    fields = {}
    list.each do |v|
      fields[v[0]] << v[1] if fields[v[0]].present?
      fields.merge!({v[0] => [v[1]]}) if !fields[v[0]].present?
    end
    fields
  end

  def hash_of_association
    fields = self.fields_in_hash(self.list_of_fields)
    
    case self.report_on
    when 'booking'
      ret = {:room => {:only => fields['room']||[], :include => {:tags => {:only => fields['tags']||[]}, :building => {:only => fields['building']||[], :include => {:tags => {:only => fields['tags']||[]}, :sub_area => {:only => fields['sub_area']||[], :include => {:area => {:only => fields['area']||[]}}}}}}},
             :room_schema =>{:only => fields['room_schema']||[]},
             :booking_category =>{:only => fields['booking_category']||[]},
             :arrangement =>{:include => {:booker => {:only => fields['booker']||[]},:customer => {:only => fields['customer']||[]}}, :only => fields['arrangement']||[]},
             :booking_attendees =>{:only => fields['booking_attendees']||[]},
             :cancellation_reason =>{:only => fields['cancellation_reason']||[]},
             :payments =>{:only => fields['payments']||[], :include => {:user => {:only => fields['user']||[]}}},
             :events =>{:only => fields['events']||[]},
             :booked_equipment =>{:only => fields['booked_equipment']||[]}, 
             :booked_supplier_items => {:only => fields['booked_supplier_items']||[], :include => {:supplier_item =>{:only => fields['supplier_item']||[], :include => {:supplier =>{:only => fields['supplier']||[]}}}}}}

    when 'payment'
      ret = {:user => {:only => fields['user']||[]}, :booking => {:only => fields['booking']||[], :include => {
                         :room => {:only => fields['room']||[], :include => {:building => {:only => fields['building']||[], :include => {:sub_area => {:only => fields['sub_area']||[], :include => {:area => {:only => fields['area']||[]}}}}}}},
                         :room_schema =>{:only => fields['room_schema']||[]},
                         :booking_category =>{:only => fields['booking_category']||[]},
                         :arrangement =>{:only => fields['arrangement']||[], :include => {:booker => {:only => fields['booker']||[]},:customer => {:only => fields['customer']||[]}}},
                         :booking_attendees =>{:only => fields['booking_attendees']||[]},
                         :cancellation_reason =>{:only => fields['cancellation_reason']||[]},
                         :booked_equipment =>{:only => fields['booked_equipment']||[]},
                         :booked_supplier_items => {:only => fields['booked_supplier_items']||[], :include => {:supplier_item =>{:only => fields['supplier_item']||[], :include => {:supplier =>{:only => fields['supplier']||[]}}}}}}},
            :events =>{:only => fields['events']||[]}}

    when 'room'
      ret = {:building => {:only => fields['building']||[], :include => {:sub_area => {:only => fields['sub_area']||[], :include => {:area => {:only => fields['area']||[]}}}}},
             :bookings => {:only => fields['bookings']||[], :include =>  {:room_schema =>{:only => fields['room_schema']||[]},
                                                                         :booking_category =>{:only => fields['booking_category']||[]},
                                                                         :arrangement =>{:include => {:booker => {:only => fields['booker']||[]},:customer => {:only => fields['customer']||[]}}, :only => fields['arrangement']||[]},
                                                                         :booking_attendees =>{:only => fields['booking_attendees']||[]},
                                                                         :cancellation_reason =>{:only => fields['cancellation_reason']||[]},
                                                                         :payments =>{:only => fields['payments']||[], :include => {:user => {:only => fields['user']||[]}}},
                                                                         :events =>{:only => fields['events']||[]},
                                                                         :booked_equipment =>{:only => fields['booked_equipment']||[]},
                                                                         :booked_supplier_items => {:only => fields['booked_supplier_items']||[], :include => {:supplier_item =>{:only => fields['supplier_item']||[], :include => {:supplier =>{:only => fields['supplier']||[]}}}}}}}}
    when 'customer'
      ret = {:arrangements =>{:include => {:booker => {:only => fields['booker']||[]},
             :bookings => {:only => fields['bookings']||[], :include =>  {:room => {:only => fields['room']||[], :include => {:building => {:only => fields['building']||[], :include => {:sub_area => {:only => fields['sub_area']||[], :include => {:area => {:only => fields['area']||[]}}}}}}},
                                                                         :room_schema =>{:only => fields['room_schema']||[]},
                                                                         :booking_category =>{:only => fields['booking_category']||[]},
                                                                         :booking_attendees =>{:only => fields['booking_attendees']||[]},
                                                                         :cancellation_reason =>{:only => fields['cancellation_reason']||[]},
                                                                         :payments =>{:only => fields['payments']||[], :include => {:user => {:only => fields['user']||[]}}},
                                                                         :events =>{:only => fields['events']||[]},
                                                                         :booked_equipment =>{:only => fields['booked_equipment']||[]},
                                                                         :booked_supplier_items => {:only => fields['booked_supplier_items']||[], :include => {:supplier_item =>{:only => fields['supplier_item']||[], :include => {:supplier =>{:only => fields['supplier']||[]}}}}}}}}, :only => fields['arrangements']||[]}}
    when 'supplier'
      fields['items'] = fields['supplier_items']
      ret = {:items =>{:only => fields['items']||[], :include => {:booked_supplier_items => {:only => fields['booked_supplier_items']||[], :include => {:booking => {:only => fields['booking']||[], :include => {:room => {:only => fields['room']||[], :include => {:building => {:only => fields['building']||[], :include => {:sub_area => {:only => fields['sub_area']||[], :include => {:area => {:only => fields['area']||[]}}}}}}},
             :room_schema =>{:only => fields['room_schema']||[]},
             :booking_category =>{:only => fields['booking_category']||[]},
             :arrangement =>{:include => {:booker => {:only => fields['booker']||[]},:customer => {:only => fields['customer']||[]}}, :only => fields['arrangement']||[]},
             :booking_attendees =>{:only => fields['booking_attendees']||[]},
             :cancellation_reason =>{:only => fields['cancellation_reason']||[]},
             :payments =>{:only => fields['payments']||[], :include => {:user => {:only => fields['user']||[]}}},
             :events =>{:only => fields['events']||[]},
             :booked_equipment =>{:only => fields['booked_equipment']||[]}}}}}}}}
    end

    # Filter out any empty only fields so the associations don't get called when serialized
    filter = lambda {|assoc|
      assoc.delete_if do |k,v|
        if v.is_a? Hash
          if v[:include]
            filter.call v[:include]
            v.all? {|k2,v2| v2.nil? || v2.empty? }
          else
            v.has_key?(:only) && v[:only].empty?
          end
        end
      end
    }
    filter.call ret
  end

  def join_string
    known_joins = case self.report_on
    when 'booking'
        [["arrangements", "arrangements.id = bookings.arrangement_id"],
        ["users bookers", "bookers.id = arrangements.booker_id"],
        ["users customers", "customers.id = arrangements.customer_id"],
        ["booked_equipments", "booked_equipments.booking_id = bookings.id"],
        ["booked_supplier_items", "booked_supplier_items.booking_id = bookings.id"],
        ["supplier_items", "supplier_items.id = booked_supplier_items.supplier_item_id"],
        ["suppliers", "suppliers.id = supplier_items.supplier_id"],
        ["booking_attendees", "booking_attendees.booking_id = bookings.id"],
        ["booking_categories", "booking_categories.id = bookings.booking_category_id"],
        ["cancellation_reasons", "cancellation_reasons.id = bookings.cancellation_reason_id"],
        ["events", "events.eventable_id = bookings.id AND events.eventable_type = 'Booking'"],
        ["payments", "payments.booking_id = bookings.id"],
        ["users", "users.id = payments.user_id"],
        ["rooms", "rooms.id = bookings.room_id"],
        ["buildings", "buildings.id = rooms.building_id"],
        ["sub_areas", "sub_areas.id = buildings.sub_area_id"],
        ["areas", "areas.id = sub_areas.area_id"],
        ["taggings", "(buildings.id = taggings.taggable_id AND taggings.taggable_type = 'Building')"],
        ["tags tags_buildings", "(tags_buildings.id = taggings.tag_id)"],
        ["taggings tags_rooms_join", "(rooms.id = tags_rooms_join.taggable_id AND tags_rooms_join.taggable_type = 'Room')"],
        ["tags tags_rooms", "(tags_rooms.id = tags_rooms_join.tag_id)"],
        ["room_schemas", "room_schemas.id = bookings.room_schema_id"]]
    when 'payment'
        [["bookings", "bookings.id = payments.booking_id"],
        ["arrangements", "arrangements.id = bookings.arrangement_id"],
        ["users bookers", "bookers.id = arrangements.booker_id"],
        ["users customers", "customers.id = arrangements.customer_id"],
        ["booked_equipments", "booked_equipments.booking_id = bookings.id"],
        ["booked_supplier_items", "booked_supplier_items.booking_id = bookings.id"],
        ["supplier_items", "supplier_items.id = booked_supplier_items.supplier_item_id"],
        ["suppliers", "suppliers.id = supplier_items.supplier_id"],
        ["booking_attendees", "booking_attendees.booking_id = bookings.id"],
        ["booking_categories", "booking_categories.id = bookings.booking_category_id"],
        ["cancellation_reasons", "cancellation_reasons.id = bookings.cancellation_reason_id"],
        ["rooms", "rooms.id = bookings.room_id"],
        ["buildings", "buildings.id = rooms.building_id"],
        ["sub_areas", "sub_areas.id = buildings.sub_area_id"],
        ["areas", "areas.id = sub_areas.area_id"],
        ["taggings", "(buildings.id = taggings.taggable_id AND taggings.taggable_type = 'Building')"],
        ["tags tags_buildings", "(tags_buildings.id = taggings.tag_id)"],
        ["taggings tags_rooms_join", "(rooms.id = tags_rooms_join.taggable_id AND tags_rooms_join.taggable_type = 'Room')"],
        ["tags tags_rooms", "(tags_rooms.id = tags_rooms_join.tag_id)"],
        ["room_schemas", "room_schemas.id = bookings.room_schema_id"],
        ["events", "events.eventable_id = payments.id AND events.eventable_type = 'Payment'"],
        ["users", "users.id = payments.user_id"]]
    when 'room'
        [["bookings", "bookings.room_id = rooms.id"],
        ["arrangements", "arrangements.id = bookings.arrangement_id"],
        ["users bookers", "bookers.id = arrangements.booker_id"],
        ["users customers", "customers.id = arrangements.customer_id"],
        ["booked_equipments", "booked_equipments.booking_id = bookings.id"],
        ["booked_supplier_items", "booked_supplier_items.booking_id = bookings.id"],
        ["supplier_items", "supplier_items.id = booked_supplier_items.supplier_item_id"],
        ["suppliers", "suppliers.id = supplier_items.supplier_id"],
        ["booking_attendees", "booking_attendees.booking_id = bookings.id"],
        ["booking_categories", "booking_categories.id = bookings.booking_category_id"],
        ["cancellation_reasons", "cancellation_reasons.id = bookings.cancellation_reason_id"],
        ["events", "events.eventable_id = bookings.id AND events.eventable_type = 'Booking'"],
        ["payments", "payments.booking_id = bookings.id"],
        ["users", "users.id = payments.user_id"],
        ["room_schemas", "room_schemas.id = bookings.room_schema_id"],
        ["buildings", "buildings.id = rooms.building_id"],
        ["sub_areas", "sub_areas.id = buildings.sub_area_id"],
        ["areas", "areas.id = sub_areas.area_id"],
        ["taggings", "(buildings.id = taggings.taggable_id AND taggings.taggable_type = 'Building')"],
        ["tags tags_buildings", "(tags_buildings.id = taggings.tag_id)"],
        ["taggings tags_rooms_join", "(rooms.id = tags_rooms_join.taggable_id AND tags_rooms_join.taggable_type = 'Room')"],
        ["tags tags_rooms", "(tags_rooms.id = tags_rooms_join.tag_id)"]]
    when 'customer'
        [["arrangements", "arrangements.customer_id = users.id"],
        ["users customers", "customers.id = arrangements.customer_id"],
        ["users bookers", "bookers.id = arrangements.booker_id"],
        ["bookings", "bookings.arrangement_id = arrangements.id"],
        ["booked_equipments", "booked_equipments.booking_id = bookings.id"],
        ["booked_supplier_items", "booked_supplier_items.booking_id = bookings.id"],
        ["supplier_items", "supplier_items.id = booked_supplier_items.supplier_item_id"],
        ["suppliers", "suppliers.id = supplier_items.supplier_id"],
        ["booking_attendees", "booking_attendees.booking_id = bookings.id"],
        ["booking_categories", "booking_categories.id = bookings.booking_category_id"],
        ["cancellation_reasons", "cancellation_reasons.id = bookings.cancellation_reason_id"],
        ["events", "events.eventable_id = bookings.id AND events.eventable_type = 'Booking'"],
        ["payments", "payments.booking_id = bookings.id"],
        ["rooms", "rooms.id = bookings.room_id"],
        ["buildings", "buildings.id = rooms.building_id"],
        ["sub_areas", "sub_areas.id = buildings.sub_area_id"],
        ["areas", "areas.id = sub_areas.area_id"],
        ["taggings", "(buildings.id = taggings.taggable_id AND taggings.taggable_type = 'Building')"],
        ["tags tags_buildings", "(tags_buildings.id = taggings.tag_id)"],
        ["taggings tags_rooms_join", "(rooms.id = tags_rooms_join.taggable_id AND tags_rooms_join.taggable_type = 'Room')"],
        ["tags tags_rooms", "(tags_rooms.id = tags_rooms_join.tag_id)"],
        ["room_schemas", "room_schemas.id = bookings.room_schema_id "]]
    when 'supplier'
        [["supplier_items", "supplier_items.supplier_id = suppliers.id"],
        ["booked_supplier_items", "booked_supplier_items.supplier_item_id = supplier_items.id"],
        ["bookings", "bookings.id = booked_supplier_items.booking_id"],
        ["arrangements", "arrangements.id = bookings.arrangement_id"],
        ["users bookers", "bookers.id = arrangements.booker_id"],
        ["users customers", "customers.id = arrangements.customer_id"],
        ["booked_equipments", "booked_equipments.booking_id = bookings.id"],
        ["booking_attendees", "booking_attendees.booking_id = bookings.id"],
        ["booking_categories", "booking_categories.id = bookings.booking_category_id"],
        ["cancellation_reasons", "cancellation_reasons.id = bookings.cancellation_reason_id"],
        ["events", "events.eventable_id = bookings.id AND events.eventable_type = 'Booking'"],
        ["payments", "payments.booking_id = bookings.id"],
        ["users", "users.id = payments.user_id"],
        ["rooms", "rooms.id = bookings.room_id"],
        ["buildings", "buildings.id = rooms.building_id"],
        ["sub_areas", "sub_areas.id = buildings.sub_area_id"],
        ["areas", "areas.id = sub_areas.area_id"],
        ["taggings", "(buildings.id = taggings.taggable_id AND taggings.taggable_type = 'Building')"],
        ["tags tags_buildings", "(tags_buildings.id = taggings.tag_id)"],
        ["taggings tags_rooms_join", "(rooms.id = tags_rooms_join.taggable_id AND tags_rooms_join.taggable_type = 'Room')"],
        ["tags tags_rooms", "(tags_rooms.id = tags_rooms_join.tag_id)"],
        ["room_schemas", "room_schemas.id = bookings.room_schema_id"]]
    end

    # Get used tables
	  used_tables = []
    used_tables = list_of_fields.map {|f| f[0].pluralize if f[0] }.uniq.compact if list_of_fields.present?
	
  	#HACK - need to include tagging join tables if tags selected!
  	used_tables = used_tables | ["taggings"] if (used_tables & ["tags", "buildings"]).length == 2
  	used_tables = used_tables | ["taggings tags_rooms_join"] if (used_tables & ["tags", "rooms"]).length == 2

    # Remove unused tables from join hash, since some names have aliases just pick the first part
    known_joins.delete_if {|k,v| !used_tables.include?(k.split(' ')[0]) }
    known_joins.map {|table, join| "LEFT JOIN #{table} ON #{join}" }.join(' ')
  end

  def get_af_parameter_value_proc(form, field)
  
	#any combination that doesn't explicitly return a proc will fall through to the end where
	#we return a default proc that itself returns an empty string
  
	case self.report_on
		### BOOKING ###
		when "booking"
			case form
				when "booking_form"
					return Proc.new do |data| data.booking_form.present? ? data.booking_form[field] : "" end
				when "payment_form"
				
				when "customer_details"
					return Proc.new do |data| data.arrangement.customer.customer_details.present? ? data.arrangement.customer.customer_details[field] : "" end
			end
		### PAYMENT ###
		when "payment"
			case form
				when "booking_form"
					return Proc.new do |data| data.booking.booking_form.present? ? data.booking.booking_form[field] : "" end
				when "payment_form"
					return Proc.new do |data| data.payment_form.present? ? data.payment_form[field] : "" end
				when "customer_details"
					return Proc.new do |data| data.booking.arrangement.customer.customer_details.present? ? data.booking.arrangement.customer.customer_details[field] : "" end
			end
		### ROOM ###
		when "room"
			case form
				when "booking_form"
				
				when "payment_form"
				
				when "customer_details"
					
			end

		### CUSTOMER ###
		when "customer"
			case form
				when "booking_form"
				
				when "payment_form"
				
				when "customer_details"
					return Proc.new do |data| data.customer_details.present? ? data.customer_details[field] : "" end
			end
		### SUPPLIER ###
		when "supplier"
			case form
				when "booking_form"
				
				when "payment_form"
				
				when "customer_details"
					
			end
	end
	
	#catch-all for any cases not explictly handled yet
	return Proc.new do |data| "" end
	
  end
  
  def af_parameter_procs
  	procs = []
  	self.list_of_af_parameters.each do |form,field,condition,value|
  		case condition
  			when "matches"
  				p = Proc.new do |data| self.get_af_parameter_value_proc(form,field).call(data) == value end
  			when "does_not_match"
  				p = Proc.new do |data| self.get_af_parameter_value_proc(form,field).call(data) != value end
  			when "contains"
  				p = Proc.new do |data| self.get_af_parameter_value_proc(form,field).call(data).include?(value) end
  			when "does_not_contain"
  				p = Proc.new do |data| !self.get_af_parameter_value_proc(form,field).call(data).include?(value) end
  		end
		  procs << p
	  end  
	  return procs
  end
  
  def generate(params = {})  
  	@data = []
    parameters = {}
    
    if self.list_of_parameters.present? # Must run these parameters before fetching data as they are used in querying it
    	self.list_of_parameters.each do |type,name|
    		case type
    			when "start_date"
    				temp_date = params[name] || Time.zone.now.to_s
    				parameters[name.to_sym] = Time.zone.parse(temp_date).to_s(:db)

    			when "end_date"
    				temp_date = params[name] || Time.zone.now.to_s
    				parameters[name.to_sym] = (Time.zone.parse(temp_date) + 24.hours - 1.second).to_s(:db)
       
    			else
    				parameters[name.to_sym] = params[name] || ""
    		end
  	  end
	  end
	
	  @data = self.report_on.sub("customer","user").camelize.constantize.find(:all, :conditions => ["#{self.sql}", parameters], :joins => self.join_string).uniq

    if self.list_of_parameters.present? # Modify parameters values for to_xml data
      self.list_of_parameters.each do |type,name|
		    case type
			    when "keywords"
				    parameters[name.to_sym] = parameters[name.to_sym].collect {|keyword| Tag.find(keyword.to_i)}
		    end
	    end
    end
	
  	#if we have a list of AF parameters, need to filter the list manually
  	if self.list_of_af_parameters.present?
		
  		filter_procs = self.af_parameter_procs
		
  		@data = @data.find_all{|item| 
  			filter_procs.inject(true){|result, filter|
  				result = result and filter.call(item)
  			}
  		}
  	end
		
  	#need to loop through data if a database update is required
  	if (self.update_field_name.present? and self.update_field_value.present?)
  		@data.each do |item| 
		
  			#if the report query involves a join, ActiveRecord will return the data
  			#objects with the readonly flag set, so attempting to update them
  			#directly will fail.  Thus we need to find the object again and issue
  			#the update on the new object.
			
  			updateitem = self.report_on.sub("customer","user").camelize.constantize.find(item.id)
		
  			#set current_updater for those objects that support it
  			updateitem.current_updater = self.current_user if updateitem.respond_to?(:current_updater=) && self.current_user.present?
			
  			updateitem.update_attribute(update_field_name, update_field_value)
			
  			#record update in event log
  			#don't need to handle booking, as these are already handled elsewhere
  			if self.report_on != "booking"
  				Event.create!(
  					:eventable => updateitem,
  					:action    => "update",
  					:details   => {update_field_name => update_field_value},
  					:user_id   => (self.current_user.present? ? self.current_user.id : nil)
  				)
  			end
  		end
  	end
      	
  	fields = {}
  	af_fields = {}
	
  	fields = self.fields_in_hash(self.list_of_fields) if self.list_of_fields.present?
  	af_fields = self.fields_in_hash(self.list_of_af_fields) if self.list_of_af_fields.present?

  	Hash::XML_FORMATTING['datetime'] = Proc.new { |datetime| datetime.in_time_zone.short_datetime }
  	# Same parameters for each record
  	# Generate XML
  	xml = Builder::XmlMarkup.new(:indent => 2)
  	xml.instruct!
  	xml.report do |xml|
  	  # with current time
  	  xml.tag! 'report-generated', Time.current
  	  # the parameters supplied, including normal Rails/URL junk

  	  parameters.to_xml(:builder => xml, :skip_instruct => true, :root => 'report_params')
	  
  	  #if report is based on bookings, we add additional calculated fields to the results
  	  if self.report_on == 'booking'
  			total_paid = @data.inject(0){|running_total, booking| running_total += booking.amount_paid}
  			# should this come from another payment_total column on bookings or total - balance_outstanding ?
  			total_bookings = @data.size
	
  			xml.report_totals do |xml|
  				xml.tag! "amount_paid", (total_paid*100).to_f.round/100.to_f
  				xml.tag! "booking_count", total_bookings
  			end 
  	  end
	  
  	  @data.to_xml(:af_hash => af_fields,
  				   :only => fields[self.report_on], :include => self.hash_of_association,
  				   :skip_instruct => true, :builder => xml)
  	end
	  @xml = xml.target!
	
  	if !@data.empty?
  		return @xml
  	else
  		return ""
  	end
  end
  
  #################################################################################################
  # Report import/export functionality
  #################################################################################################
  
  def export
  	xml = Builder::XmlMarkup.new(:indent => 2)
  	xml.instruct!
  	xml.report do |xml|
  		xml.tag! "name", self.name
  		xml.tag! "report_on", self.report_on
  		xml.tag! "sql", self.sql
  		xml.tag! "update_field_name", self.update_field_name
  		xml.tag! "update_field_value", self.update_field_value
		
  		list_of_af_fields
  		list_of_parameters
  		list_of_af_parameters
  		viewable_by
		
  		xml.list_of_fields do |xml|
  			self.list_of_fields.each do |table,column|
  				xml.field do |xml|
  					xml.tag! "table", table
  					xml.tag! "column", column
  				end
  			end
  		end if self.list_of_fields.present?
		
  		xml.list_of_af_fields do |xml|
  			self.list_of_af_fields.each do |form,field|
  				xml.af_field do |xml|
  					xml.tag! "form", form
  					xml.tag! "field", field
  				end
  			end
  		end if self.list_of_af_fields.present?
		
  		xml.list_of_parameters do |xml|
  			self.list_of_parameters.each do |name,type|
  				xml.parameter do |xml|
  					xml.tag! "name", name
  					xml.tag! "type", type
  				end
  			end
  		end if self.list_of_parameters.present?
		
  		xml.list_of_af_parameters do |xml|
  			self.list_of_af_parameters.each do |form,field,condition,value|
  				xml.af_parameter do |xml|
  					xml.tag! "form", form
  					xml.tag! "field", field
  					xml.tag! "condition", condition
  					xml.tag! "value", value
  				end
  			end
  		end if self.list_of_af_parameters.present?
		
  		xml.viewable_by do |xml|
  			self.viewable_by.each do |group|
  				xml.tag! "group", group
  			end
  		end if self.viewable_by.present?

  	end
  	xml.target!
  end
  
  def self.import(xml)
  	report = Report.new
  
  	#catch XML structure errors and report as generic 'XML' error
  	begin
  
  		doc = REXML::Document.new(xml)
  		report.name 				      = doc.elements['report'].elements['name'].text
  		report.report_on 		    	= doc.elements['report'].elements['report_on'].text
  		report.sql					      = doc.elements['report'].elements['sql'].text
  		report.update_field_name	= doc.elements['report'].elements['update_field_name'].text
  		report.update_field_value	= doc.elements['report'].elements['update_field_value'].text
		
  		list_of_fields = []
		  doc.elements.each("//report/list_of_fields/field") do |field| 
				list_of_fields << [field.elements["table"].text, field.elements["column"].text]
  		end
		  report.list_of_fields = list_of_fields if list_of_fields.any?
		
  		list_of_af_fields = []
  		doc.elements.each("//report/list_of_af_fields/af_field") do |af_field| 
  			list_of_af_fields << [af_field.elements["form"].text, af_field.elements["field"].text]
  		end
  		report.list_of_af_fields = list_of_af_fields if list_of_af_fields.any?
		
		  list_of_parameters = []
  		doc.elements.each("//report/list_of_parameters/parameter") do |parameter| 
  			list_of_parameters << [parameter.elements["name"].text, parameter.elements["type"].text]
  		end
  		report.list_of_parameters = list_of_parameters if list_of_parameters.any?
		
  		list_of_af_parameters = []
  		doc.elements.each("//report/list_of_af_parameters/af_parameter") do |af_parameter| 
  			list_of_af_parameters << [af_parameter.elements["form"].text, af_parameter.elements["field"].text,af_parameter.elements["condition"].text, af_parameter.elements["value"].text]
  		end
  		report.list_of_af_parameters = list_of_af_parameters if list_of_af_parameters.any?
		
  		viewable_by = []
  		doc.elements.each("//report/viewable_by/group") do |group| 
  			viewable_by << group.text
  		end
		  report.viewable_by = viewable_by if viewable_by.any?
	  rescue
		  raise "Report XML invalid"
	  end
	  report.save!
  end
end
