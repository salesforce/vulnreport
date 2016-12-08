##
# Copyright (c) 2016, salesforce.com, inc.
# All rights reserved.
# Licensed under the BSD 3-Clause license. 
# For full license text, see LICENSE.txt file in the repo root  or https://opensource.org/licenses/BSD-3-Clause
##

##
# Vulnerability types (e.g. Stored XSS). Essentially a specialized RecordType for {Vulnerability}
class VulnType
	include DataMapper::Resource

	property :id,				Serial 						#@return [Integer] Primary Key
	property :name,				String, :length => 100		#@return [String] VulnType Name (for internal use)
	property :label,			String, :length => 100 		#@return [String] VulnType label (for export/public reports)
	property :html,				Text 						#@return [String] HTML describing the Vulnerability to be used in exported reports
	property :enabled,			Boolean, :default => true 	#@return [Boolean] True if this VulnType is enabled for use in new {Vulnerability} objects
	property :priority,			Integer 					#@return [Integer] Default priority level for this VulnType. Can be overridden by {Vulnerability}. 0 => Critical, 1 => High, 2 => Medium, 3 => Low, 4 => Informational
	property :cwe_mapping,		Integer						#@return [Integer] The ID of the CWE this VulnType maps to (optional)

	property :enabledRTs,		CommaSeparatedList			#@return [Text] Comma-separated list of IDs of {RecordType}s that use this VulnType
	property :enabledSections,	CommaSeparatedList			#@return [Integer] IDs of Sections enabled on this VulnType. From SECT_TYPE enum.
	property :defaultSource, 	Integer, :default => 0 		#@return [Integer] ID of the default {VulnSource} for this type. Default 0 (manual testing)

	##
	# Get functional VulnType label. Returns label if one exists, otherwise name.
	# @return [String] Label of VulnType to use in reporting
	def getLabel
		if(self.label.nil? || self.label.strip.empty?)
			return self.name
		else
			return self.label
		end
	end

	##
	# Get VulnType object based on name
	# @param name [String] Name of VulnType to get
	# @return [VulnType] first matching VulnType
	def self.getTypeByName(name)
		first(:conditions => ["lower(name) = ?", name.downcase])
	end

	##
	# Get all VulnTypes enabled for a specific {RecordType}
	# @param rtid [Integer] ID of {RecordType} to get VulnTypes for
	# @return [Array<VulnType>] VulnTypes enabled and enabled for given RecordType
	def self.getByRecordType(rtid)
		ret = Array.new

		all(:enabled => true).each do |vt|
			types = vt.enabledRTs
			if(!types.nil?)
				types.each do |t|
					if(t.to_i == rtid.to_i)
						ret << vt
						break
					end
				end
			end
		end

		return ret
	end

	##
	# @return [String] Link to CWE definition on Mitre's website if CWE-mapping exists
	def cwe_link
		if(self.cwe_mapping.nil? || self.cwe_mapping <= 0)
			return nil
		else
			return "https://cwe.mitre.org/data/definitions/#{self.cwe_mapping}.html"
		end
	end
end