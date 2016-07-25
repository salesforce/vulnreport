##
# Copyright (c) 2016, salesforce.com, inc.
# All rights reserved.
# Licensed under the BSD 3-Clause license. 
# For full license text, see LICENSE.txt file in the repo root  or https://opensource.org/licenses/BSD-3-Clause
##

##
# Record type definition
class RecordType
	include DataMapper::Resource

	property :id,				Serial 							#@return [Integer] Primary Key
	property :object,			Integer 						#@return [LINK_TYPE] Object this RecordType defines a type for
	property :active,			Boolean, :default => true 		#@return [Boolean] True if this RecordType is active
	
	property :name,				String,	:length => 100			#@return [String] Name of the RecordType
	property :description,		Text 							#@return [String] Description of the RecordType
	property :isLinked,			Boolean, :default => false 		#@return [Boolean] True if this RecordType links to an object using a {VRLinkedObject}
	property :linkedObjectKey,	String							#@return [LINK_TYPE] The key of the {VRLinkedObject} this RecordType is linked to (as an invariant)
	property :exportFormat,		Integer, :default => 0 			#@return [ExportFormat] Report format this RecordType uses

	property :canBePassedToCon,	Boolean, :default => false 		#@return [Boolean] True if this RecordType can be passed to a contractor for testing
	property :canBeProvPassed,	Boolean, :default => false 		#@return [Boolean] True if {Test}s on {Application}s of this RecordType can be provisionally passed
	property :defaultPrivate,	Boolean, :default => false 		#@return [Boolean] If True, {Application}s of this RecordType will be marked private by default
	property :vulnPriorities,	String, :length => 255, :default => "Critical,High,Medium,Low,Informational" #@return [String] Stores the 5 vuln priority strings (Critical, High, Medium, Low, Informational) in CSV form. Limit 50 chars per priority.

	##
	# Get the human-readable string for a given vulnerability priority level 
	# of a vuln on an {Application} of this RecordType
	# @param level [VULN_PRIORITY] The priority level to get the string for
	# @return [String] Vuln priority level string (e.g. "Critical")
	def getVulnPriorityString(level)
		levelStrArray = self.vulnPriorities.split(",")
		
		if(level == VULN_PRIORITY::CRITICAL)
			if(levelStrArray[0].nil? || levelStrArray[0].empty?)
				return "Critical"
			else
				return levelStrArray[0]
			end
		elsif(level == VULN_PRIORITY::HIGH)
			if(levelStrArray[1].nil? || levelStrArray[1].empty?)
				return "High"
			else
				return levelStrArray[1]
			end
		elsif(level == VULN_PRIORITY::MEDIUM)
			if(levelStrArray[2].nil? || levelStrArray[2].empty?)
				return "Medium"
			else
				return levelStrArray[2]
			end
		elsif(level == VULN_PRIORITY::LOW)
			if(levelStrArray[3].nil? || levelStrArray[3].empty?)
				return "Low"
			else
				return levelStrArray[3]
			end
		elsif(level == VULN_PRIORITY::INFORMATIONAL)
			if(levelStrArray[4].nil? || levelStrArray[4].empty?)
				return "Informational"
			else
				return levelStrArray[4]
			end
		else
			return "None"
		end
	end

	##
	# Set the human-readable string for a given vulnerability priority level 
	# of a vuln on an {Application} of this RecordType
	# @param level [VULN_PRIORITY] The priority level to set the string for
	# @param str [String] Vuln priority level string (e.g. "Critical")
	def setVulnPriorityString(level, str)
		levelStrArray = self.vulnPriorities.split(",")
		return false if(level >= levelStrArray.size)
		return false if(str.length > 50)

		levelStrArray[level] = str
		self.vulnPriorities = levelStrArray.join(',')

		return self.save
	end

	##
	# Get active RecordTypes that refer to {Application} objects
	# @return [Array<RecordType>] Matching RecordTypes
	def self.appRecordTypes()
		all(:active => true, :object => LINK_TYPE::APPLICATION)
	end

	##
	# Get all RecordTypes that refer to {Application} objects
	# @return [Array<RecordType>] Matching RecordTypes
	def self.allAppRecordTypes()
		all(:object => LINK_TYPE::APPLICATION)
	end
end