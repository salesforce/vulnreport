##
# Copyright (c) 2016, salesforce.com, inc.
# All rights reserved.
# Licensed under the BSD 3-Clause license. 
# For full license text, see LICENSE.txt file in the repo root  or https://opensource.org/licenses/BSD-3-Clause
##

##
# VRLinkedObject is the parent class for custom links between {Application}s and external systems.
#
# An {Application} {RecordType} can be set as a linked record type, at which point it can specify a 
# VRLinkedObject to utilize. This subclass specifies the type of Entity ID to link to, the generation
# of linked information to display on the single_app view, and actions to take on the external system
# when a {Test} related to the {Application} in Vulnreport changes status.
class VRLinkedObject
	class << self

		def inherited(obj)
			objs << obj
		end

		def objs
			@objs ||= []
		end

		def vrlo_key(key=nil)
			@vrlo_key = key.to_s if !key.nil?
			@vrlo_key ||= self.key
		end

		def vrlo_name(name=nil)
			@vrlo_name = name.to_s if !name.nil?
			@vrlo_name ||= self.name
		end

		def each(&block)
			objs.each do |member|
				block.call(member)
			end
		end

		def getByKey(key)
			objs.each do |obj|
				if(obj.vrlo_key == key)
					return obj
				end
			end

			return nil
		end

		##
		# Called when loading the single_app view of an {Application} of a {RecordType} linked to this object.
		# Generates the linked object information panel for the view as well as any error/alert messages to display
		# above the nav breadcrumbs.
		# @param app [Application] The {Application} object being loaded
		# @param uid [Integer] The ID of the {User} calling the page
		# @param params [Hash] The params from the Sinatra page load is passed
		# @param env [Hash] The Sinatra request environment is passed
		# @return [Hash] Hash of :success - Boolean, :errstr - String of error text if success is false, 
		#  :infoPanelHtml - HTML for the info panel and :alerts - Array of alert messages where each element is a hash of :color, :html,
		#  :customMenuItems - Array of menu items where each element is a hash of :icon, :text, :href, :authMethods, :isDropdown, :dropdownOpts (Array of hashes - :href and :text)
		def getLinkedObjectInfoPanel(app, uid, params, env)
			raise "NotImplemented"
		end

		##
		# Called when loading the single_test view of a {Test} attached to an {Application} of a {RecordType} linked to this object.
		# Generates any alerts for display above the breadcrumbs
		# @param app [Application] The {Application} object of the {Test} being loaded
		# @param test [Test] The {Test} object being loaded
		# @param uid [Integer] The ID of the {User} calling the page
		# @return [Hash] Hash of :success - Boolean, :errstr - String of error text if success is false, 
		#  :alerts - Array of alert messages where each element is a hash of :color, :html,
		#  :customMenuItems - Array of menu items where each element is a hash of :icon, :text, :href, :authMethods, :isDropdown, :dropdownOpts (Array of hashes - :href and :text)
		def getTestAlerts(app, test, uid)
			raise "NotImplemented"
		end

		##
		# Called after an {Application} of a {RecordType} linked to this object is created.
		# @param app [Application] The newly created {Application} object
		# @param uid [Integer] ID of the {User} who performed the action
		# @return [Hash] - Hash of :success - Boolean and :alerts - Array of alert messages. Each element is a hash of :color, :html
		def doCreateAppActions(app, uid)
			raise "NotImplemented"
		end

		##
		# Called after an {Application} of a {RecordType} linked to this object is set to a new owner
		# @param app [Application] The {Application} object being updated
		# @param uid [Integer] ID of the {User} who performed the action
		# @param newOwnerUid [Integer] ID of the {User} who is the new owner
		def doAppReassignedActions(app, uid, newOwnerUid)
			raise "NotImplemented"
		end

		##
		# Called when a {Test} is created/put in progress on an {Application} of a {RecordType} linked to this object.
		# @param app [Application] The {Application} object being updated
		# @param test [Test] The newly created/in progress {Test} object
		# @param uid [Integer] ID of the {User} who performed the action
		# @return [Hash] - Hash of :success - Boolean and :alerts - Array of alert messages. Each element is a hash of :color, :html
		def doNewTestActions(app, test, uid)
			raise "NotImplemented"
		end

		##
		# Called when an existing {Test} is put in progress on an {Application} of a {RecordType} linked to this object.
		# @param app [Application] The {Application} object being updated
		# @param test [Test] The newly created/in progress {Test} object
		# @param uid [Integer] ID of the {User} who performed the action
		# @return [Hash] - Hash of :success - Boolean and :alerts - Array of alert messages. Each element is a hash of :color, :html
		def doInProgressActions(app, test, uid)
			raise "NotImplemented"
		end

		##
		# Called when a {Test} is marked passed on an {Application} of a {RecordType} linked to this object.
		# @param app [Application] The {Application} object being updated
		# @param test [Test] The {Test} object being updated
		# @param uid [Integer] ID of the {User} who performed the action
		# @return [Hash] - Hash of :success - Boolean and :alerts - Array of alert messages. Each element is a hash of :color, :html
		def doPassActions(app, test, uid)
			raise "NotImplemented"
		end

		##
		# Called when a {Test} is marked provisionally passed on an {Application} of a {RecordType} linked to this object.
		# @param app [Application] The {Application} object being updated
		# @param test [Test] The {Test} object being updated
		# @param uid [Integer] ID of the {User} who performed the action
		# @return [Hash] - Hash of :success - Boolean and :alerts - Array of alert messages. Each element is a hash of :color, :html
		def doProvPassActions(app, test, uid)
			raise "NotImplemented"
		end

		##
		# Called when a {Test} is marked failed on an {Application} of a {RecordType} linked to this object.
		# @param app [Application] The {Application} object being updated
		# @param test [Test] The {Test} object being updated
		# @param uid [Integer] ID of the {User} who performed the action
		# @return [Hash] - Hash of :success - Boolean and :alerts - Array of alert messages. Each element is a hash of :color, :html
		def doFailActions(app, test, uid)
			raise "NotImplemented"
		end

		##
		# Called when a {Application} is deleted
		# @param app [Application] The {Application} object being updated
		# @param uid [Integer] ID of the {User} who performed the action
		# @return [Hash] - Hash of :success - Boolean and :errstr if failed 
		def doDeleteAppActions(app, uid)
			raise "NotImplemented"
		end

		##
		# @return [String] The name or text representation of the object that this application is linked to.
		def getLinkedObjectText(app)
			raise "NotImplemented"
		end

		##
		# @return [String] The URL of the object that this application is linked to.
		def getLinkedObjectURL(app)
			raise "NotImplemented"
		end

		##
		# Called when linking an Application to a linked object ID to validate the ID. Can mutate EID.
		# @param eid [String] EID to validate
		# @param app [Application] App object that will be attached to this EID
		# @return [Hash] Hash of :valid [Boolean] and :eid with the valid (possibly mutated) EID. If :valid is false
		#  also contains :errstr.
		def validateEntityID(eid, app)
			raise "NotImplemented"
		end

		##
		# Called by Vulnreport when a system-wide search is initiated (from /search) that includes a {RecordType}. 
		# that links to this Linked Object. If specific results or additional results based on the linked object 
		# should be returned in the search results they can be via this method.
		# @return [Array <Hash>] Array of results, each element is a hash with keys :text and :link
		def doSearch(q)
			raise "NotImplemented"
		end
	end

	delegate :vrlo_key, to: :class
	delegate :vrlo_name, to: :class

end