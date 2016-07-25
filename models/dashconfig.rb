##
# Copyright (c) 2016, salesforce.com, inc.
# All rights reserved.
# Licensed under the BSD 3-Clause license. 
# For full license text, see LICENSE.txt file in the repo root  or https://opensource.org/licenses/BSD-3-Clause
##

##
# Dashboard configuration - can be created/edited by admins and assigned to orgs. Two types of DashConfigs - declarative and custom.
# Declarative DashConfigs are configured through admin interface. Custom DashConfigs are code files registered on Vulnreport init.
# Custom DashConfigs can declare custom settings that will be editable via the admin interface.
class DashConfig
	include DataMapper::Resource

	property :id,				Serial 						#@return [Integer] Primary Key
	property :name,				String 						#@return [Name] Name of the Dashboard
	property :description,		Text 						#@return [String] User description of the Dashboard
	property :active,			Boolean, :default => true 	#@return [Boolean] True if this DashConfig is active and available for use

	property :showStats,		Boolean, :default => true 	#@return [Boolean] True if the stats bar should be shown. This is used for declarative dashconfigs only.
	property :stats,			Object 						#@return [Array<Hash>] Data for stats blocks. Array of hashes, each each with keys icon,text,color,type,rt.  This is used for declarative dashconfigs only.
	property :panels,			Object 						#@return [Array<Hash>] Data for panels. Array of hashes, each with keys type,rt,title,zerotext,maxwks.  This is used for declarative dashconfigs only.

	property :customCode,		Boolean, :default => false 	#@return [Boolean] True if this dashconfig is custom code (registered on initialization).
	property :customKey,		String 						#@return [String] Unique key for this dashconfig. Used for custom code dashconfigs only.
	property :customSettings,	Object 						#@return [Hash<Hash>] Custom settings for this dashconfig. Used for custom code dashconfigs only. Hash is key => Hash of name, value

	##
	# Add a panel to the dashboard
	# @param panel [Hash] Hash representing the panel with keys :title, :type, :rt, :maxwks, and :zerotext
	# @return [Boolean] True if successful
	def addPanel(panel)
		self.panels << panel
		self.make_dirty(:panels)
		
		return self.save
	end

	##
	# Get settings hash for dashboard (custom code only)
	# @return [Hash] Settings
	def getSettingsForDash
		if(!self.customCode)
			return {}
		else
			settings = Hash.new
			customSettings.each do |k,v|
				settings[k] = v[:val]
			end

			return settings
		end
	end

end