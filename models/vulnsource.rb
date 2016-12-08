##
# Copyright (c) 2016, salesforce.com, inc.
# All rights reserved.
# Licensed under the BSD 3-Clause license. 
# For full license text, see LICENSE.txt file in the repo root  or https://opensource.org/licenses/BSD-3-Clause
##

# Sources that vulns can come from for tracking/analysis. Default (0 - not in db) is manual testing.
class VulnSource
	include DataMapper::Resource

	property :id,				Serial 							#@return [Integer] Primary Key
	
	property :name,				String							#@return [String] Name of the VulnSource
	property :shortname, 		String 							#@return [String] Short name for use in single_vuln UI dropdown
	property :description, 		Text 							#@return [String] Description of the VulnSource (admin notes only)
	property :enabled,			Boolean, :default => true 		#@return [Boolean] True if this VulnSource is enabled for use in new {Vulnerability} objects

	##
	# Get function VulnSource short name
	# @return [String] Short name of VulnSource to use in UI dropdown
	def getLabel
		if(self.shortname.nil? || self.shortname.strip.empty?)
			return self.name
		else
			return self.shortname
		end
	end

end