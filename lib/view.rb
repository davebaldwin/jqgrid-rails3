# From https://gist.github.com/6391
class Hash
	def rmerge (other_hash)
    	r = {}
		merge(other_hash) do |key, oldval, newval|
			r[key] = oldval.class == self.class ? oldval.rmerge(newval) : newval
		end
	end
end

module JqgridView

	private
	
	class Javascript
		def initialize (code)
			@code = code
		end

		def to_s
			@code
		end
		
		def to_json
			@code
		end
	end

  	def jqgrid_stylesheets(theme = "default")
      stylesheet_link_tag 	"jqgrid/themes/#{theme}/jquery-ui-1.8.custom.css", 
        					'jqgrid/ui.jqgrid.css', 
							'jqgrid/ui.multiselect.css',
        					:cache => "jqgrid-#{theme}-css"
    end

	def jqgrid_javascripts
		locale = I18n.locale rescue :en

		# Try and use the source version instead of the minified version.  Rails 3.1.0 will
		# minify it in production automatically (assuming you are using the asset pipeline).
		if Rails::VERSION::MAJOR >= 3 && Rails::VERSION::MINOR >= 1
			javascript_include_tag 	"jqgrid/i18n/grid.locale-#{locale}.js",
									'jqgrid/ui.multiselect.js', 
									'jqgrid/jquery.jqGrid.src.js',
			        				:cache => 'jqgrid-js'
		else
			javascript_include_tag  'jqgrid/jquery-ui-1.8.custom.min.js',
									"jqgrid/i18n/grid.locale-#{locale}.js",
									'jqgrid/ui.multiselect.js', 
									'jqgrid/jquery.jqGrid.min.js',
			        				:cache => 'jqgrid-js'
		end
	end

	# View helper to force a grid to be reloaded based on a control changing.
	def reload_grid (grid_name)
		"javascript:jQuery('##{grid_name}').trigger('reloadGrid')"
	end
	
	@@app_grid_options = {}
	def self.jqgrid_app_grid_options (options)
		@@app_grid_options = options
	end

	@@app_pager_options = {}
	def self.jqgrid_app_pager_options (options)
		@@app_pager_options = options
	end
	
	
	# http://www.trirand.com/jqgridwiki/doku.php?id=wiki:options 
	def jqgrid (caption, id, url, columns = [], options = {})
 		@id = id

     	default_options = 
        { 
          	# Can be nil or false to disregard all errors, :default to show the errors or a
		  	# string holding the js error handler name you want to use (its code is part of the view).
			:error_handler       => :default,  
			
   
			# No searching via the filterbar is done if this is nil or false, otherwise it takes a hash of the filter options.
			# http://www.trirand.net/documentation/php/_2v70waupp.htm
         	:search				 => {:searchOnEnter => false},

			:url				 => "#{url}?",
			:editurl			 => "#{url}",
			:caption			 => caption,
			:datatype			 => :json,

			# Can be :inline to allow inline editing in the table or :form to pop up a form to do the editing in.
			# If it is nil or false then no editing can be done.
			:edit_method		 => :inline,
			
			# http://www.trirand.com/jqgridwiki/doku.php?id=wiki:navigator
			:add                 => false,
			:delete              => false,
			:view                => false,          
			:edit_options 		=> {:closeOnEscape => true, :modal => true, :recreateForm => true, :width => 300, :closeAfterEdit => true,
										:mtype => 'PUT', 
										:onclickSubmit => Javascript.new("function(params, postdata) {params.url = '#{url}/' + postdata.#{id}_id}"),
										:afterSubmit => Javascript.new("function(r, data) {return ERROR_HANDLER_NAME(r,data,'edit')}")},

			:add_options 		=> {:closeOnEscape => true, :modal => true, :recreateForm => true, :width => 300, :closeAfterAdd => true,
										:mtype => 'POST', 										
										:afterSubmit => Javascript.new("function(r, data) {return ERROR_HANDLER_NAME(r,data,'add')}")},

			:delete_options 	=> {:closeOnEscape => true, :modal => true, :mtype => 'DELETE',
										:serializeDelData => Javascript.new("function() {return ''}"),
										:onclickSubmit =>  Javascript.new("function(params, postdata) {params.url = '#{url}/' + postdata}")},

			:ajaxRowOptions => {:type => 'PUT' },
			:height				=> 500,
			:resizable			=> true,
			
			# :width				=> 600,
			:viewrecords		=> true,			# doesn't update correctly when not paging??
			:recordtext			=> '{2} records',		# 'Posts {0} - {1} of {2}',
		   	:rowNum				=> 10,
			:rowTotal			=> 2000,


			:rowlist             => [10,25,50,100],				# not the jqgrid default ???
			:context_menu        => false,
			:column_chooser		 => false,
        }

		# Combine all options with default having the lowest priority, then any app level options and finally view specific
		# options.
 		@grid_options = default_options.rmerge(@@app_grid_options).rmerge(options)
  		@grid_methods = []
		@grid_events = {}
		@grid_globals = []

		@grid_globals << "var #{id}_grid_columns = #{columns.map {|c| c[:name]}.inspect}"
		
    	# Take out the higher level options and convert to options and jqgrid methods.		
		
		grid_loaded_options (:grid_loaded)
		context_menu_options(:context_menu)
		selection_options(:selection, :selection_handler)
		error_handler_options (:error_handler)
		pager_options(:pager)	
		inline_edit(url)
 		master_details
		augment_post_data
		navigator_options
 		search_options(:search)
		resizable
		column_chooser
		
		
		# Generate columns data
		gen_columns(columns)

		@grid_options.delete(:edit_method)
		
    	# Generate required Javascript & html to create the jqgrid
		"<script type = 'text/javascript'>
			#{grid_globals}

			jQuery(document).ready(function()
			{
				jQuery('##{@id}').jqGrid({
					#{grid_options}
				})				

				#{grid_methods}
			})
			</script>

		<div id='flash_alert' style='display:none;padding:0.7em;' class='ui-state-highlight ui-corner-all'></div>
		<table id='#{@id}' class='scroll' cellpadding='0' cellspacing='0'></table>
		<div id='#{@id}_pager' class='scroll' style='text-align:center;'></div>
		"    
    end

    private
 
	# Returns an array of js properties from a hash, i.e. each hash entry is converted to key: value_as_js_type
	def js_properties (hsh)
		hsh ? hsh.map {|key, value|  "#{key}: #{value.to_json}"} : []
	end
	
	# Convert the grid options to js properties.
	def grid_options
		grid_events
		js_properties(@grid_options).join(",\n")
	end
	
	def grid_methods
		@grid_methods.join("\n")
	end

	def grid_globals
		@grid_globals.join("\n")
	end

	# We may add more than one function to be triggered on an event.
	def add_event (event, function)
		if @grid_events[event]
			@grid_events[event] << function
		else
			@grid_events[event] = [function]
		end
	end
	
	# Convert any grid events into grid options once any proxy functions have been introduced to cope with multiple
	# handlers for the same event.
	def grid_events
		@grid_events.each do |event, functions|
			if functions.length == 1
				@grid_options[event] = functions[0]
			else
				# Extract the declaration so we know how to call the converted functions and how we are going to be called.
				declaration = functions[0].to_s[/(.*?)\{/, 1]
				arguments = declaration[/(\(.*?\))/, 1]
				proxy_function = declaration + "{\n"
				functions.each_with_index do |f, i|
					# Convert the anonymous functions into real functions.
					@grid_methods << f.to_s.sub(/function/, "function #{event}_#{i}")

					# Add to the proxy function
					proxy_function << "\t#{event}_#{i}#{arguments}\n"
				end
				@grid_options[event] = Javascript.new(proxy_function += "}")
			end
		end
	end
	
	# Enable filtering (by default)
	def search_options (options)
		options = @grid_options.delete(options)
		if options
			@grid_methods << 
			%Q^jQuery("##{@id}").navButtonAdd("##{@id}_pager", {caption: "", title: $.jgrid.nav.searchtitle, buttonicon :'ui-icon-search', onClickButton:function(){ jQuery("##{@id}")[0].toggleToolbar() } })^
			@grid_methods << %Q^jQuery("##{@id}").filterToolbar({#{js_properties(options).join(', ')}}); jQuery("##{@id}")[0].toggleToolbar()^
		end
    end

	# When  options[:error_handler] == nil 		then use the null error handler (it does nothing so ignores any errors)
	# When  options[:error_handler] == :default then use the default error handler and displays the errors.
	# When  options[:error_handler] == a string then the string holds the name of the error handler to use.  The code is provided
	#  									as part of the view.
	def error_handler_options (handler)
	   	handler = @grid_options.delete(handler)

		case handler
			when nil
				# Null error handler - just ignore all errors.
				@error_handler_name = 'null_error_handler'
				 @grid_methods << 
					%Q^function null_error_handler (r, data, action) 
					{
						return true
					}^
			when :default
			    # Construct default error handler code to display the error
				@error_handler_name = 'default_error_handler'
		        @grid_methods <<
		 			%Q^function default_error_handler (r, data, action) 
					{
			       		var resText = JSON.parse (r.responseText)
			          	if (resText[0])
					  	{
			            	$('#flash_alert').html('<div id="error_explanation">' + resText[1] + '</div>')
			            	$('#flash_alert').slideDown()
			            	window.setTimeout(function() {$('#flash_alert').slideUp()}, 3000)
			              	return false
			         	}
						else
						{
			        		return true
			        	}
					}^			    
			else
				# Custom error handler
				@error_handler_name = handler
		end
	end		
				
	# Enable inline editing with a double click.  After the edit (assuming no errors) the row is reloaded from
	# the results of the save operation so any changes to the formatting of the saved data or virtual attributes
	# are made visible.  Note if the edit changes the sorting order or filtered selection then this will not be 
	# shown - this could be fixed by reloading the grid, but this then looses the row highlight and it is problematic
	# to re-establish it again as the row may not be visible if the sort order changed or the row is filtered out.
	def inline_edit (url)
		if @grid_options[:edit_method] == :inline
			# The code is passed in as a option so must not be converted into a quoted string when
			# converted to json.  After the edit is completed the row is selected again.
			@grid_globals << "var lastsel, lastedit"		
			add_event :ondblClickRow, Javascript.new(
			%Q^function(id){
	        	if (id && id !== lastedit)
				{
	            	jQuery('##{@id}').restoreRow(lastsel)
				}
            	lastedit = id
            	jQuery('##{@id}').editRow(id, true, null, #{@error_handler_name}, '#{url}/' + id , null, 
					function(id, resp) {
						var response = JSON.parse (resp.responseText)
						jQuery('##{@id}').setRowData(lastedit, response[2])
					}) 
	        }^)
	
			# If we are in the middle of an inline edit and the user selects another row then abandon the edit.
			add_event :onSelectRow, Javascript.new(
			%Q^function(id){
	        	if (id && id !== lastsel && id != lastedit)
				{
	            	jQuery('##{@id}').restoreRow(lastsel)
	            	lastsel = id
					lastedit = null
	          	} 
	        }^)
			
		end
	end

	# The options hash key is now :master_details and the value for this key is either a hash (for a single detail) 
	# or an array of hashes (for multiple details).  A detail hash has the following keys	
	#     :grid_id				the id of the grid to use to display the detail view
	#     :caption				caption string (can have $column_name entries)
	#     :foreign_key_column	the column in the master table holding the foreign key
	# 	  :detail_foreign_key	the attribute in the detail table to match the master foreign key against (can be omitted if the same)

	def master_details
		if details = @grid_options.delete(:master_details)
			details = [details] if details.kind_of? Hash
			@grid_globals << %Q^var slave_grids = {#{details.map {|d| "#{d[:grid_id]}:true"}.join(', ')}}^
			details.each do |detail|
				# Make details of the foreign key available as globals so an add on a detail grid can use them.
				@grid_globals << "var #{detail[:grid_id]}_foreign_id_attribute = null"
				@grid_globals << "var #{detail[:grid_id]}_foreign_id = null"
				caption = detail[:caption]
				if caption !~ /\$/
					caption += "$#{detail[:foreign_key_column]}"
				end
				add_event :onSelectRow, Javascript.new(
					%Q^
					function(ids) { 
							#{detail[:grid_id]}_foreign_id_attribute = '#{detail[:foreign_key_column]}'
							#{detail[:grid_id]}_foreign_id = jQuery('##{@id}').getRowData (ids)['#{detail[:foreign_key_column]}']
							caption = '#{caption}'.replace (/\\$([a-zA-Z0-9_.]+)/g, function (str, p1) {return jQuery('##{@id}').getRowData (ids)[p1]})
							jQuery("##{detail[:grid_id]}").setGridParam({postData: {foreign_id_attribute: '#{detail[:detail_foreign_key] || detail[:foreign_key_column]}', foreign_id: #{detail[:grid_id]}_foreign_id}})
								.setCaption(caption)
								.trigger('reloadGrid'); 							
					}^
				)
				
				# Clear the slave detail grid when ever the master detail is reloaded (as nothing should be selected).
				add_event :loadComplete, Javascript.new(
					%Q^
					function(data) { 
							#{detail[:grid_id]}_foreign_id_attribute = null
							#{detail[:grid_id]}_foreign_id = null
							jQuery("##{detail[:grid_id]}").setCaption("#{detail[:caption].gsub(/\$[a-zA-Z0-9_.]+/, '')}")
								.trigger('reloadGrid'); 							
					}^
				
				)
			end
		else
			@grid_globals << %Q^var slave_grids = {}^	
		end
	end
	
	# Enable grid_loaded callback
    # When data are loaded into the grid, call the Javascript function options[:grid_loaded] (defined by the user)
	def grid_loaded_options (callback)
		if callback = @grid_options.delete(callback)
			add_event :loadComplete, Javascript.new("function() {{#{callback}()}")
		end
	end

	# Context menu
	# See http://www.trendskitchens.co.nz/jquery/contextmenu/
	# http://www.hard-bit.net/files/jqGrid-3.5/ContextMenu.html
	# http://www.hard-bit.net/blog/?p=171
	# set to {:menu_bindings => xx, :menu_id => yy}, as needed.
	def context_menu_options (option)
		if cm = @grid_options.delete(option)
			@grid_methos <<
			%Q^
				afterInsertRow: function(rowid, rowdata, rowelem){
					$('#' + rowid).contextMenu('#{cm[:menu_id]}', #{cm[:menu_bindings]});
			}^
		end
	end

	def selection_options (mode, handler)
		mode = @grid_options.delete(:selection)
		@selection_handler = @grid_options.delete(:selection_handler)
		case mode
			when nil
			when :multi_selection				# checkboxes
				@grid_options[:multiselect] = true
				@grid_methos <<
				%Q^
		          jQuery("##{@id}_select_button").click(function() { 
		            var s; s = jQuery("##{id}").getGridParam('selarrrow'); 
		            #{handler}(s); 
		            return false;
		          });^

			when :direct_selection
				# Enable direct selection (when a row in the table is clicked)
			    # The javascript function created by the user (options[:selection_handler]) will be called with the selected row id as a parameter
			    @grid_methods <<
			  	%Q^onSelectRow: function(id){ 
			       if(id){ 
			            #{handler}(id); 
			       } 
			    }^
				
			when :button
		      # Enable selection link, button
		      # The javascript function created by the user (options[:selection_handler]) will be called with the selected row id as a parameter
			    @grid_methods <<
		        %Q^
		        jQuery("##{@id}_select_button").click( function(){ 
		          var id = jQuery("##{@id}").getGridParam('selrow'); 
		          if (id) { 
		            #{handler}(id); 
		          } else { 
		            alert("Please select a row");
		          }
		          return false; 
		        });^
			else
				raise "Unknown value for jqGrid option[:selection]: #{mode}"
		end
	end	
	
	# http://www.trirand.com/jqgridwiki/doku.php?id=wiki:pager
	def pager_options (pager)
		# pager = @@app_grid_options.merge(@grid_options.delete(pager))
		# return if pager.empty?
		
		pager_name = "##{@id}_pager"

		# Add in the pager specific options
		@grid_options[:pager] = pager_name
		# rowList
		# viewRecords
	end
	
	# http://www.trirand.com/jqgridwiki/doku.php?id=wiki:navigator
	def navigator_options
		edit 		 = @grid_options[:edit_method] == :form
    	add          = @grid_options.delete(:add)
		delete       = @grid_options.delete(:delete)
		view         = @grid_options.delete(:view)

		edit_options 	= @grid_options.delete(:edit_options)
		add_options 	= @grid_options.delete(:add_options)
		delete_options 	= @grid_options.delete(:delete_options)

		edit_options 	= {} if !edit
		add_options 	= {} if !add
		delete_options 	= {} if !delete

	    js = %Q^jQuery("##{@id}").navGrid('##{@id}_pager',
			{edit: #{edit}, add: #{add}, del: #{delete}, view: #{view}, search: false, refresh: true},
				{#{js_properties(edit_options).join(", ")}},
				{#{js_properties(add_options).join(", ")}},
				{#{js_properties(delete_options).join(", ")}}
		)
		^

		@grid_methods << js.gsub(/ERROR_HANDLER_NAME/, "#{@error_handler_name}") 
	end
	
	def column_chooser
		if @grid_options[:column_chooser]
			@grid_methods <<
	        %Q^
			jQuery("##{@id}").navButtonAdd("##{@id}_pager", {
	    		caption: "Columns", title: "Reorder Columns",
	    		onClickButton: function (){jQuery("##{@id}").jqGrid('columnChooser')}})
			^
		end
	end
		
	# We need to inject additional items into the post data returned to the server to provide the column attributes we need to be
	# returned, foreign key attribute and its value for supporting detail grids and any external grid control values needed by the
	# controller because they are tested directly or used to augment the search criteria.
	# The external controls are passed in in the grid options with a key of :external_controls as a hash or array of hashes.  Each
	# hash has the following entries:
	#      :control_id          the id of the control to interrogate.
	#      :attrib_name         the params attribute name used to pass the control's value back to the server
	#      :use_in_search		set to true if the attribute (direct, virtual or path to attribute in another table) is to be used
	# 							to qualify the search/filter of the displayed results.  If it is not true then the controller is 
	# 							assumed to use it in some way.
	#      :mapping				if present, is a hash keyed by the control's values with each entry being a 'value map hash'.
	# The value map hash has the following entries:
	# 		:attrib_name		same use as above, but may be absent for this control value to be a no-op.
	# 		:use_in_search 		same as above.
	#       :value 				if present this value will be used instead of the control's value
	# The mapping feature allows different control values to be treated differently, maybe to not be flagged to the controller, or 
	# to use a different attribute name, etc.. 
	
	def augment_post_data
		raise "Cannot override 'serializeRowData' option as it is already set" 				if @grid_options[:serializeRowData]
		raise "Cannot override 'serializeGridData' option as it is already set" 			if @grid_options[:serializeGridData]
		raise "Cannot override 'add_options[:onclickSubmit]' option as it is already set" 	if @grid_options[:add_options][:onclickSubmit] 	

		grid_columns = "postdata.grid_columns = #{@id}_grid_columns"

		# If the foreign id attribute is null then we remove it from postdata as this seems to be persistent across grid operations
		# and by removing it will cause the detail grid to go empty, maybe as a result of the master grid being reloaded.
		slave_detail = 
		%Q^
		if (slave_grids.#{@id})
		{
			postdata.slave_detail = true
			if (#{@id}_foreign_id_attribute == null)
			{
				delete postdata.foreign_id_attribute
				delete postdata.foreign_id						
			}
		}
		^	

		external_controls =  @grid_options.delete(:external_controls)

		if external_controls
			external_controls = [external_controls] if external_controls.kind_of? Hash
			
			# If the attrib_name changes from invocation to invocation the previous attrib_name will still hang around
			# do delete them all before we start.
			attrib_params = []
			external_controls.each do |c|
				attrib_params << c[:attrib_name]
				c[:values].each {|k, v| attrib_params << v[:attrib_name]} if c[:values]
			end	
			delete_attrib_params = attrib_params.compact.uniq.map {|p| "delete postdata.#{p}"}.join("\n")

	       	control_access =
		 	%Q^
			#{delete_attrib_params}
			external_controls = #{external_controls.to_json}
			$.each (external_controls, function (i, c)
				{
					control_value = document.getElementById(c.control_id).value
					if (c.mapping)
					{
						if (c.mapping[control_value])
						{
							if (c.mapping[control_value].attrib_name)
							{
								if (c.mapping[control_value].value)
									postdata[c.mapping[control_value].attrib_name] = c.mapping[control_value].value
								else
									postdata[c.values[control_value].attrib_name] = value
								if (c.mapping[control_value].use_in_search)
									postdata._search = 'true'
							}
						}
					}
					else
					{
						postdata[c.attrib_name] = value
						if (c.use_in_search)
							postdata._search = 'true'
					}		
				}
			)
			^						
		end

		@grid_options[:serializeRowData] = 
			Javascript.new("function (postdata)
	 						{
								delete postdata.oper
								#{grid_columns}
								#{slave_detail}
								#{control_access}
								return postdata
							}")
	
		@grid_options[:serializeGridData] = 
			Javascript.new("function (postdata) 
							{
								#{grid_columns}
								#{slave_detail}
								#{control_access}
								return postdata
							}")
	

		# If the foreign_id is defined for this grid then this grid is a detail grid and in order to add a
		# new entry to it we need to provide the foreign key attribute name and its value.  For a master grid
		# or when no detail grid exists then this is effectively ignored.
		@grid_options[:add_options][:onclickSubmit] = 
			Javascript.new("function(params, postdata) 
							{	
								delete postdata.oper
								#{grid_columns}
								#{slave_detail}
								#{control_access}
								return postdata
							}")	
	end
	
    # Recalculate width of grid based on parent container.
    # ref: http://www.trirand.com/blog/?page_id=393/feature-request/Resizable%20grid/
	def resizable
		return if !@grid_options.delete(:resizable)
		@grid_methods <<
		%Q^
		function _recalc_width(){
          if (grids = jQuery('"#{@id}".ui-jqgrid-btable:visible')) {
            grids.each(function(index) {
              gridId = jQuery(this).attr('id');
              gridParentWidth = jQuery('#gbox_' + gridId).parent().width();
              jQuery('#' + gridId).setGridWidth(gridParentWidth);
            });
          }
        };

        jQuery(window).bind('resize', _recalc_width);
    	^
	end
	
	def gen_columns (columns)
		# Add in the missing property.
		columns.each {|c| c[:index] = c[:name]}
		
		# Convert each column into the required form.  It is wrapped in a Javascript object to prevent
		# it from being converted to json again.
	 	cols = columns.map {|c| "{" + js_properties(c).join(", ") + "}"}
		@grid_options[:colModel] = Javascript.new("[#{cols.join(', ')}]")		
	end
end

class ActionView::Base
	include JqgridView
end
