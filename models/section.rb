##
# Copyright (c) 2016, salesforce.com, inc.
# All rights reserved.
# Licensed under the BSD 3-Clause license. 
# For full license text, see LICENSE.txt file in the repo root  or https://opensource.org/licenses/BSD-3-Clause
##

##
# A single piece of information relating to a {Vulnerability} that has been found and logged
class Section
	include DataMapper::Resource

	property :id, 					Serial 							#@return [Integer] Primary Key
	property :vulnerability_id,  	Integer   						#@return [Integer] ID of {Test} the Vulnerability belongs to
	property :type, 				Integer							#@return [SECT_TYPE] Type of section from {SECT_TYPE}
	property :body, 				Text, :length => 1024*1024*12 	#@return [String] Body of section (details of vuln). In case of SSHOT or PAYLOAD is B64 encoded file data. Max 12MB.
	property :fname,				String 							#@return [String] Original filename for SSHOT or PAYLOAD
	property :created_at, 			DateTime						#@return [DateTime] Date/Time Section created (DM Handled)
	property :updated_at, 			DateTime						#@return [DateTime] Date/Time Section last updated (DM Handled)
	property :show, 				Boolean, :default => true 		#@return [Boolean] True if section should be shown on exported reports. If false, only visibile in Vulnreport test view.
	property :listOrder,			Integer, :default => 0			#@return [Integer] Order in which to display (relative to other Sections on same {Vulnerability})

	belongs_to :vulnerability 										#@return [Vulnerability] Vulnerability that this Section belongs to

	##
	# Get Human-readable string representing Section's type
	# @return [String] Human-readable section type
	def type_str
		return "URL" if self.type == SECT_TYPE::URL
		return "File" if self.type == SECT_TYPE::FILE
		return "Screenshot" if self.type == SECT_TYPE::SSHOT
		return "Output" if self.type == SECT_TYPE::OUTPUT
		return "Code" if self.type == SECT_TYPE::CODE
		return "Notes" if self.type == SECT_TYPE::NOTES
		return "Payload" if self.type == SECT_TYPE::PAYLOAD
	end

	##
	# Get textarea edit size for UI
	# @return [String] edit size for UI
	def edit_size
		if (self.type == SECT_TYPE::OUTPUT || self.type == SECT_TYPE::CODE || self.type == SECT_TYPE::NOTES)
			return "large"
		else
			return "small"
		end
	end

	##
	# Return the HTML formatted output of this section for use in export reports
	## @return [String] HTML output
	def html_formatted
		return "" if self.type == SECT_TYPE::PAYLOAD

		v = self.vulnerability

		str = "<div id=\"section_#{self.id}\"><h4 class=\"sectHeader\">#{self.type_str}" 
		str += "</h4><div id=\"section_body_#{self.id}\" class=\"sectBody\">"

		if self.type == SECT_TYPE::SSHOT
			str += "<img src=\"data:image/png;base64,#{self.body}\" alt='Screenshot' style=\"max-width:870px;\" />"
		elsif self.type == SECT_TYPE::URL
			str += "#{Rack::Utils::escape_html(self.body)}"
		elsif self.type == SECT_TYPE::OUTPUT
			str += "<pre class=\"code\">\n"+Rack::Utils::escape_html(self.body)+"</pre>"
		elsif self.type == SECT_TYPE::CODE
			str += "<pre class=\"code\">\n"+Rack::Utils::escape_html(self.body)+"</pre>"
		elsif self.type == SECT_TYPE::NOTES
			str += "<pre>\n"+Rack::Utils::escape_html(self.body)+"</pre>"
		else
			str += "#{Rack::Utils::escape_html(self.body)}"
		end

		str += "</div></div>"
		str.force_encoding('UTF-8')

		return str
	end

end