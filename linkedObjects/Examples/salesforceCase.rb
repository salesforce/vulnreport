##
# A sample VR Linked Object, linking Vulnreport to the Case object in Salesforce.
# This VRLO will display information about a Salesforce Case in Vulnreport when it is linked to
# a Vulnreport Application. Upon assignment, creation and resolution of security Tests in Vulnreport,
# the Salesforce Case Object will be updated with status and owner information.
#
# !!
# This VRLO is only for example purposes, and you should modify it or write your 
# own for your use case and business logic.
#
# For full documentation about writing VRLO integrations, see the /lib/VRLinkedObject.rb
# code documentation and http://vulnreport.io/documentation#interfaces.
##

##
# Copyright (c) 2016, salesforce.com, inc.
# All rights reserved.
# Licensed under the BSD 3-Clause license. 
# For full license text, see LICENSE.txt file in the repo root  or https://opensource.org/licenses/BSD-3-Clause
##

require './lib/salesforce'

class SalesforceCase < VRLinkedObject
	vrlo_key :sfdc_case
	vrlo_name :"Salesforce Case"

	def self.h(str)
		return Rack::Utils.escape_html(str)
	end

	#Get case information from Salesforce and display in Vulnreport
	def self.getLinkedObjectInfoPanel(app, uid, params, env)
		soql = "SELECT Id, Contact.Id, Contact.Name, Subject, Description, Type, Reason, Status, Priority, Origin FROM Case WHERE Id='#{app.linkId}'"
		caseInfo = Salesforce.doQuery("de", soql)

		if(caseInfo[:success])
			caseObj = caseInfo[:records][0]

			html = "<b>Case Subject:</b> #{h(caseObj[:Subject])} (<a href=\"https://na3.salesforce.com/#{caseObj[:Id]}\" target=\"_blank\">#{caseObj[:Id]}</a>)<br />"
			html += "<b>Case Type:</b> #{caseObj[:Type]}<br />"
			html += "<b>Case Reason:</b> #{caseObj[:Reason]}<br />"
			html += "<b>Case Priority:</b> #{caseObj[:Priority]} (Origin: #{caseObj[:Origin]})<br /><br />"
			html += "<b>Case Description</b><br />#{caseObj[:Description]}"

			return {:success => true, :infoPanelHtml => html, :alerts => [], :customMenuItems => []}
		else
			return {:success => false, :errstr => caseInfo[:fault][:faultstring]}
		end
	end

	def self.getTestAlerts(app, test, uid)
		#noop
		return {:success => true, :alerts => [], :customMenuItems => []}
	end

	def self.doCreateAppActions(app, uid)
		#noop
		return {:success => true}
	end

	#Change case owner in Salesforce when owner changes in Vulnreport
	def self.doAppReassignedActions(app, uid, newOwnerUid)
	end

	def self.doDeleteAppActions(app, uid)
		#noop
		return {:success => true}
	end

	#Set case to 'working' status in Salesforce and assign owner when a test is started in Vulnreport.
	# Owner is assigned based on Vulnreport User's External EID
	def self.doNewTestActions(app, test, uid)
		soql = "SELECT Id, OwnerId, Status FROM Case WHERE Id='#{app.linkId}'"
		caseInfo = Salesforce.doQuery("de", soql)

		if(caseInfo[:success])
			caseObj = caseInfo[:records][0]
			caseObj[:Status] = "Working"

			u = User.get(uid)
			if(!u.nil? && !u.extEID.nil? && u.extEID.start_with?('005'))
				caseObj[:OwnerId] = u.extEID
			end

			updateRet = Salesforce.doUpdate("de", caseObj)
			if(updateRet[:success])
				return {:success => true}
			else
				return {:success => false, :errstr => updateRet[:fault][:faultstring]}
			end
		else
			return {:success => false, :errstr => caseInfo[:fault][:faultstring]}
		end
	end

	#Set case to 'working' status in Salesforce when a test is set back to in progress
	def self.doInProgressActions(app, test, uid)
		soql = "SELECT Id, OwnerId, Status FROM Case WHERE Id='#{app.linkId}'"
		caseInfo = Salesforce.doQuery("de", soql)

		if(caseInfo[:success])
			caseObj = caseInfo[:records][0]
			caseObj[:Status] = "Working"

			updateRet = Salesforce.doUpdate("de", caseObj)
			if(updateRet[:success])
				return {:success => true}
			else
				return {:success => false, :errstr => updateRet[:fault][:faultstring]}
			end
		else
			return {:success => false, :errstr => caseInfo[:fault][:faultstring]}
		end
	end

	#Close case in Salesforce as passed when Test passed in Vulnreport
	def self.doPassActions(app, test, uid)
		soql = "SELECT Id, OwnerId, Status FROM Case WHERE Id='#{app.linkId}'"
		caseInfo = Salesforce.doQuery("de", soql)

		if(caseInfo[:success])
			caseObj = caseInfo[:records][0]
			caseObj[:Status] = "Closed - Passed"

			u = User.get(uid)
			if(!u.nil? && !u.extEID.nil? && u.extEID.start_with?('005'))
				caseObj[:OwnerId] = u.extEID
			end

			updateRet = Salesforce.doUpdate("de", caseObj)
			if(updateRet[:success])
				return {:success => true}
			else
				return {:success => false, :errstr => updateRet[:fault][:faultstring]}
			end
		else
			return {:success => false, :errstr => caseInfo[:fault][:faultstring]}
		end
	end

	#Close case in Salesforce as failed when Test failed in Vulnreport
	def self.doFailActions(app, test, uid)
		soql = "SELECT Id, OwnerId, Status FROM Case WHERE Id='#{app.linkId}'"
		caseInfo = Salesforce.doQuery("de", soql)

		if(caseInfo[:success])
			caseObj = caseInfo[:records][0]
			caseObj[:Status] = "Closed - Failed"

			u = User.get(uid)
			if(!u.nil? && !u.extEID.nil? && u.extEID.start_with?('005'))
				caseObj[:OwnerId] = u.extEID
			end

			updateRet = Salesforce.doUpdate("de", caseObj)
			if(updateRet[:success])
				return {:success => true}
			else
				return {:success => false, :errstr => updateRet[:fault][:faultstring]}
			end
		else
			return {:success => false, :errstr => caseInfo[:fault][:faultstring]}
		end
	end

	#Close case in Salesforce as passed
	def self.doProvPassActions(app, test, uid)
		soql = "SELECT Id, OwnerId, Status FROM Case WHERE Id='#{app.linkId}'"
		caseInfo = Salesforce.doQuery("de", soql)

		if(caseInfo[:success])
			caseObj = caseInfo[:records][0]
			caseObj[:Status] = "Closed - Passed"

			u = User.get(uid)
			if(!u.nil? && !u.extEID.nil? && u.extEID.start_with?('005'))
				caseObj[:OwnerId] = u.extEID
			end

			updateRet = Salesforce.doUpdate("de", caseObj)
			if(updateRet[:success])
				return {:success => true}
			else
				return {:success => false, :errstr => updateRet[:fault][:faultstring]}
			end
		else
			return {:success => false, :errstr => caseInfo[:fault][:faultstring]}
		end
	end

	def self.doSearch(q)
		#noop
		return []
	end

	#Return the EID
	def self.getLinkedObjectText(app)
		return app.linkId.to_s
	end

	#Return link to Case
	def self.getLinkedObjectURL(app)
		return "https://na3.salesforce.com/#{app.linkId}"
	end

	#Ensure link EID is a valid Case EID
	def self.validateEntityID(eid, app)
		if(eid.length < 15 || eid.length > 18 || !eid.start_with?('500'))
			return {:valid => false, :errstr => "Invalid Case EID - must be EID starting with 500"}
		else
			eid = idTo18(eid)
			return {:valid => true, :eid => eid}
		end
	end

end