##
# Copyright (c) 2016, salesforce.com, inc.
# All rights reserved.
# Licensed under the BSD 3-Clause license. 
# For full license text, see LICENSE.txt file in the repo root  or https://opensource.org/licenses/BSD-3-Clause
##

##
# An application reviewed in Vulnreport. In general, an Application in Vulnreport represents an SR cycle.
class Application
	include DataMapper::Resource

	property :id,			Serial 										#@return [Integer] Primary Key
	property :record_type,	Integer, :required => true, :default => 0 	#@return [Integer] {RecordType} ID
	property :name,			String, :length => 100						#@return [String] Application name
	property :description,	Text 										#@return [String] Application description
	property :created_at, 	DateTime									#@return [DateTime] Date/Time application created (DM Handled)
	property :updated_at, 	DateTime									#@return [DateTime] Date/Time application last updated (DM Handled)
	property :owner,		Integer										#@return [Integer] ID of {User} owner of this test
	property :org_created,	Integer, :default => 1						#@return [Integer] ID of {Organization} of {User} that created this Application
	property :add_emails,	String, :length => 500 						#@return [String] CSV of additional email addresses to copy on reports

	property :global,		Boolean, :default => false 					#@return [Boolean] True if app is marked as global (any user can view)
	property :isPrivate,	Boolean, :default => false 					#@return [Boolean] True if app is marked as private (only specified users can view)
	property :allow_UIDs,	CommaSeparatedList							#@return [Array<Integer>] IDs of {User}s allowed to view if private (or override other security settings if not)

	property :geo,			Integer										#@return [GEO] Geo application is in

	has n, :tests
	has n, :flags,			:through => Resource

	##
	# Return Application linked to given {VRLinkedObject} extenral ID
	# @param eid [String] EID
	# @return [Application] Application linked to given object ID
	def self.getByLinkId(eid)
		link = Link.first(:fromType => LINK_TYPE::APPLICATION, :toType => LINK_TYPE::VRLO, :toId => eid)
		return nil if link.nil?
		return get(link.fromId)
	end

	##
	# Check if Application is linked by a {VRLinkedObject} and has a linked ID
	# @return [Boolean] true if linked, false otherwise
	def isLinked?
		links = Link.all(:fromType => LINK_TYPE::APPLICATION, :fromId => self.id, :toType => LINK_TYPE::VRLO)
		if(!links.nil? && links.size > 0)
			return true
		else
			return false
		end
	end

	##
	# Get the EID of the object Application is linked to
	# @return [String] EID of linked object
	def linkId
		link = Link.first(:fromType => LINK_TYPE::APPLICATION, :fromId => self.id, :toType => LINK_TYPE::VRLO)
		return nil if link.nil?
		return link.toId
	end

	##
	# Get the total number of {Vulnerability} objects attached to {Test}s attached to Application
	# @return [Integer] total number of vulns
	def totalvulns
		count = 0
		tests.each do |t|
			count += t.vulnerabilities.count
		end

		return count
	end

	##
	# Return {User} object of current owner
	# @return [User] owner
	def ownerUser
		if(self.owner.nil? || self.owner == 0)
			return nil
		else
			return User.get(self.owner)
		end
	end

	##
	# @return [String] name of owner user
	def ownerName
		if(self.owner.nil? || self.owner == 0)
			return "Unassigned"
		else
			return ownerUser.name
		end
	end

	##
	# Get (unformatted/code) status of Application's most recent {Test}
	# @return [String] most recent test status (unformatted)
	def lastStatus
		lastStatus = nil
		if(self.tests.nil? || self.tests.size == 0)
			lastStatus = "notests"
		elsif(self.tests.last.complete && self.tests.last.pass)
			lastStatus = "pass"
		elsif(self.tests.last.complete && !self.tests.last.pass)
			lastStatus = "fail"
		else
			lastStatus = "inprog"
		end

		return lastStatus
	end

	##
	# Get formatted status of Application's most recent {Test}
	# @return [String] most recent test status (formatted HTML string)
	def lastStatusFormatted
		lastStatus = nil
		if(self.tests.nil? || self.tests.size == 0)
			lastStatus = "No Tests"
		elsif(self.tests.last.complete && self.tests.last.pass)
			lastStatus = '<span style="color:#009933;">Pass</span>'
		elsif(self.tests.last.complete && !self.tests.last.pass)
			lastStatus = '<span style="color:#B40404;">Fail</span>'
		else
			lastStatus = "In Progress"
		end

		return lastStatus
	end

	##
	# Get icon name of flag for Application's geo
	# @return [String] flag icon name
	def geoIcon
		if(geo == GEO::USA)
			return "flag-icon-us"
		elsif(geo == GEO::JP)
			return "flag-icon-jp"
		else
			return "flag-icon-us"
		end
	end

	##
	# Get string of Application's geo
	# @return [String] Application's geo
	def geoString
		if(geo == GEO::USA)
			return "USA"
		elsif(geo == GEO::JP)
			return "Japan"
		else
			return "USA"
		end
	end

	##
	# Get Application's {RecordType}
	# @return [RecordType] Application's RecordType
	def recordType
		if(record_type.nil? || record_type == 0)
			return nil
		end

		return RecordType.get(record_type)
	end

	##
	# Get name of Application's {RecordType}
	# @return [String] Application's RecordType name
	def recordTypeName
		if(record_type.nil? || record_type == 0)
			return "Unknown"
		end

		return RecordType.get(record_type).name
	end

	##
	# Get the {VRLinkedObject} subclass for this application based on {RecordType}
	# @return [VRLinkedObject] Application's RecordType's LinkedObject class or nil if there is none
	def getVRLO
		if(record_type.nil? || record_type == 0)
			return nil
		end

		rt = RecordType.get(record_type)
		if(!rt.isLinked)
			return nil
		end

		return VRLinkedObject.getByKey(rt.linkedObjectKey)
	end

	##
	# Using the {VRLinkedObject} subclass for this application based on {RecordType}, get the URL
	# of the object that this application is linked to.
	# @return [String] The URL, or nil if there is none
	def linkedObjectURL
		vrlo = self.getVRLO
		if(vrlo.nil?)
			return nil
		end

		return vrlo.getLinkedObjectURL(self)
	end

	##
	# Using the {VRLinkedObject} subclass for this application based on {RecordType}, get the name or
	# text representation of the object that this application is linked to.
	# @return [String] The text, or nil if there is none
	def linkedObjectText
		vrlo = self.getVRLO
		if(vrlo.nil?)
			return nil
		end

		return vrlo.getLinkedObjectText(self)
	end

	def linkedObjectInfoPanel(uid, params, env)
		vrlo = self.getVRLO
		if(vrlo.nil?)
			return ""
		end

		return vrlo.getLinkedObjectInfoPanel(self, uid, params, env)
	end

	##
	# @return [Boolean] True if this application can be passed to a contractor
	def canPassToContractor?
		if(record_type.nil? || record_type == 0)
			return false
		end

		return RecordType.get(record_type).canBePassedToCon
	end

	##
	# @return [Array<Integer>] IDs of all {Flag}s associated with this Application
	def flagIds
		return self.flags.map{|f| f.id}
	end

	##
	# Get HTML formatted string of icons representing Application's flags
	# @return [String] HTML of icons
	def typeIcons
		flagIcons = Array.new
		self.flags.each do |f|
			if(!f.icon.nil? && !f.icon.strip.empty?)
				flagIcons << f
			end
		end

		str = ""
		flagIcons.each do |f|
			if(f.description.nil? || f.description.strip.empty?)
				str += "<i class=\"fa #{f.icon}\" rel=\"tooltip\" title=\"#{f.name}\"></i> "
			else
				str += "<i class=\"fa #{f.icon}\" rel=\"tooltip\" title=\"#{f.description}\"></i> "
			end
		end

		return str
	end

	##
	# Get Apps with any of the given flags and match given parameters.
	# This method passes through to Application.all with additional parameters to properly filter by flag
	# @param selectedFlags [Array] Array of flag IDs to filter by
	# @param params [Hash] Additional params to pass to Application.all
	# @return [Array<Application>] Matching Applications
	def self.allWithFlags(selectedFlags, params={})
		if(selectedFlags.include?(-1))
			return all(params)
		else
			return all({flags.id => selectedFlags}.merge(params))
		end
	end

	##
	# Count Applications that have the given flags and match given parameters.
	# This method passes through to Application.count with additional parameters to properly filter by flag
	# @param selectedFlags [Array<Integer>] Flags to filter by
	# @param params [Hash] Additional params to pass to Application.count
	# @return [Array<Application>] Number of matching Applications
	def self.countWithFlags(selectedFlags, params={})
		return allWithFlags(selectedFlags, params.merge({:fields => [:id]})).size
	end
end