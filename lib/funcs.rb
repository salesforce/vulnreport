##
# Copyright (c) 2016, salesforce.com, inc.
# All rights reserved.
# Licensed under the BSD 3-Clause license. 
# For full license text, see LICENSE.txt file in the repo root  or https://opensource.org/licenses/BSD-3-Clause
##

##
# Get the value of a {Setting} stored in database
# @param key [String] Setting key
# @return [String] Setting value
def getSetting(key)
	s = Setting.first(:setting_key => key)
	return nil if s.nil?
	return s.setting_value
end

##
# Set the value of a {Setting}. Create if none exists
# @param key [String] Setting key
# @param value [String] new/initial Setting value
# @return [Boolean] success
def setSetting(key, value)
	s = Setting.first(:setting_key => key)
	if(s.nil?)
		s = Setting.create(:setting_key => key)
	end

	s.setting_value = value
	return s.save
end

##
# Output a log string with the time and date prepended
# @param str [String] Text to output to log
def logputs(str)
	str == "" if(str.nil?)

	dstr = Time.now.strftime("[%d/%b/%Y %H:%M:%S] ")
	puts dstr + str
end

##
# Shortcut to log a basic audit record for the active user
# @param event [EVENT_TYPE] Type of event
# @param uid [Integer] User ID of actor
# @param targetType [LINK_TYPE] Type of target
# @param target [String] EID of target
# @return [AuditRecord] The created record
def logAudit(event, targetType, target, blob=nil, uid=session[:uid])
	if(blob.nil?)
		return AuditRecord.create(:event_at => DateTime.now, :event_type => event, :actor => uid, :target_a_type => targetType, :target_a => target.to_s)
	else
		return AuditRecord.create(:event_at => DateTime.now, :event_type => event, :actor => uid, :target_a_type => targetType, :target_a => target.to_s, :blob => blob.to_json)
	end
end

##
# Run a VRCron Job. This is done by invoking the cron() method on the {VRCron} subclass passed as cron.
# This is mostly called from the scheduler instance setup in registerVRCron, but also by manual runs via the admin UI.
# @param cron [VRCron] The subclass of {VRCron} to run
# @param force [Boolean] Override enabled status and run job no matter what
# @return [Object] the return from the VRCron job
def runVRCron(cron, force=false)
	begin
		cronRunData = JSON.parse(settings.redis.get("vrcron_data_#{cron.to_s}"), {:symbolize_names => true})
		if(force || cronRunData[:enabled])
			retval = cron.cron()
			cronRunData[:lastRun] = DateTime.now.to_s
			cronRunData[:lastRet] = retval.to_s
			cronRunData[:lastRunSuccess] = true
			settings.redis.set("vrcron_data_#{cron.to_s}", cronRunData.to_json)
			return retval
		end
	rescue => e
		Rollbar.error(e, "#{cron.vrcron_name} Cron Job Failure")
		cronRunData = JSON.parse(settings.redis.get("vrcron_data_#{cron.to_s}"), {:symbolize_names => true})
		cronRunData[:lastRun] = DateTime.now.to_s
		cronRunData[:lastRet] = e.to_s
		cronRunData[:lastRunSuccess] = false
		settings.redis.set("vrcron_data_#{cron.to_s}", cronRunData.to_json)
		return nil
	end
end

##
# Register a cron job with the Vulnreport scheduler instance create the appropriate
# Redis keys for Vulnreport cronjob admin/management and tracking functions.
# @param cron [VRCron] The subclass of {VRCron} being registered as a VR cronjob
# @param scheduler [Rufus::Scheduler] The Scheduler instance Vulnreport is using
# @param enabled [Boolean] Whether this cronjob should be registered as enabled. False in dev environment.
# @return [Boolean] True if registration was successful, false otherwise
def registerVRCron(cron, scheduler, enabled=true)
	logputs "VRCron Registered: #{cron.vrcron_name}"

	if(!settings.redis.exists("vrcron_data_#{cron.to_s}"))
		crondata = {:registered => false, :enabled => enabled, :name => cron.vrcron_name, :lastRun => nil}
	else
		crondata = JSON.parse(settings.redis.get("vrcron_data_#{cron.to_s}"), {:symbolize_names => true})
	end

	if(cron.vrcron_type.nil? || cron.vrcron_schedule.nil?)
		logputs "\tCron has no type or no schedule, SKIPPING REGISTRATION"
		Rollbar.error("Cron registered with no type or schedule", {:CronName => cron.vrcron_name})
		
		crondata[:error] = "Cron registered with no type or schedule"
		settings.redis.set("vrcron_data_#{cron.to_s}", crondata.to_json)
		return false
	elsif(!cron.respond_to?(:cron))
		logputs "\tCron has no cron method, SKIPPING REGISTRATION"
		Rollbar.error("Cron registered with no cron method", {:CronName => cron.vrcron_name})

		crondata[:error] = "Cron registered with no cron method"
		settings.redis.set("vrcron_data_#{cron.to_s}", crondata.to_json)
		return false
	else
		logputs "\tType: #{cron.vrcron_type}, Schedule: #{cron.vrcron_schedule}"
		crondata[:schedule_type] = cron.vrcron_type
		crondata[:schedule] = cron.vrcron_schedule
		
		if(!enabled)
			logputs "\tCron registered as not enabled"
			crondata[:enabled] = false
			settings.redis.set("vrcron_data_#{cron.to_s}", crondata.to_json)
		end

		if(cron.vrcron_type == :every)
			scheduler.every(cron.vrcron_schedule) do
				runVRCron(cron)
			end

			crondata[:registered] = true
			settings.redis.set("vrcron_data_#{cron.to_s}", crondata.to_json)
			return true
		elsif(cron.vrcron_type == :cron)
			scheduler.cron(cron.vrcron_schedule) do
				runVRCron(cron)
			end

			crondata[:registered] = true
			settings.redis.set("vrcron_data_#{cron.to_s}", crondata.to_json)
			return true
		else
			logputs "\t\tInvalid type, SKIPPING REGISTRATION"
			Rollbar.error("Cron registered invalid type", {:CronName => cron.vrcron_name, :CronType => cron.vrcron_type})
			crondata[:error] = "Cron registered invalid type"
			settings.redis.set("vrcron_data_#{cron.to_s}", crondata.to_json)
			return false
		end
	end
end

##
# Register a custom code-based {DashConfig} with Vulnreport and, if needed, create the appropriate
# database entries for a new {DashConfig} object.
# @param dc [VRDashConfig] The subclass of {VRDashConfig} being registered as a VR DashConfig
# @return [Boolean] True if registration was successful, false otherwise
def registerVRDashConfig(dc)
	logputs "VRDashConfig Registered: #{dc.vrdash_name} (key: #{dc.vrdash_key})"

	dcObj = DashConfig.first(:customKey => dc.vrdash_key.to_s)
	if(!dcObj.nil?)
		logputs "\tVRDashConfig #{dc.vrdash_name} (key: #{dc.vrdash_key}) already exists as ID #{dcObj.id}"
		# Check for any new settings
		curSettingKeys = dcObj.getSettingsForDash.keys
		
		dc.vrdash_settings.keys.each do |k|
			if(!curSettingKeys.include?(k))
				logputs "\t\tVRDashConfig #{dc.vrdash_name} (key: #{dc.vrdash_key}) has new setting (#{k.to_s})"
				dcObj.customSettings[k] = {:name => dc.vrdash_settings[k][:name], :val => dc.vrdash_settings[k][:default]}
				dcObj.make_dirty(:customSettings)
			end
		end

		dcObj.save
	else
		logputs "\tCreating VRDashConfig #{dc.vrdash_name} (key: #{dc.vrdash_key})"
		dcObj = DashConfig.create(:name => dc.vrdash_name, :active => false, :customCode => true, :customKey => dc.vrdash_key)
		logputs "\t\tCreated DC ID #{dcObj.id}"
		settingsHash = Hash.new
		
		dc.vrdash_settings.keys.each do |k|	
			settingsHash[k] = {:name => dc.vrdash_settings[k][:name], :val => dc.vrdash_settings[k][:default]}
		end
		
		dcObj.customSettings = settingsHash
		dcObj.make_dirty(:customSettings)

		dcObj.save
	end

	return true
end

##
# Finalize the registration process for custom code-based {DashConfig}s. This function ensures that
# all custom code-based DashConfigs that have been registered in the past have code files that were
# registered during init. Any custom code-based DashConfigs whose subclasses were not loaded during
# this init will be deactivated and users/orgs using them reset to default dashboard.
# @param vrdcs [Array] Array of unique keys of DashConfigs that have been registered
# @return [Void]
def finalizeVRDashConfigs(vrdcs)
	toRemove = Array.new
	dcs = DashConfig.all(:customCode => true)
	
	dcs.each do |dc|
		if(!vrdcs.include?(dc.customKey))
			toRemove << dc
		end
	end

	toRemove.each do |dcObj|
		logputs "REMOVING VRDashConfig #{dcObj.name} (key: #{dcObj.customKey}) because code file not registered"
		
		dcObj.active = false
		dcObj.save
		
		Organization.all(dashconfig => dcObj.id).each do |org|
			org.dashconfig = 0
			org.save
		end

		User.all(:dashOverride => dcObj.id).each do |u|
			u.dashOverride = 0
			u.save
		end
	end
end

##
# Register a custom {VRLinkedObject} with Vulnreport.
# @param lo [VRLinkedObject] The subclass of {VRLinkedObject} being registered
# @return [Boolean] True if registration was successful, false otherwise
def registerVRLinkedObject(lo)
	logputs "VRLinkedObject Registered: #{lo.vrlo_name} (key: #{lo.vrlo_key})"

	return true
end

##
# Finalize the registration process for custom {VRLinkedObject}s. This function ensures that
# any custom linked object used by a {RecordType} has been registered during this init. If not,
# that RT is unlinked but no linked IDs of any {Application}s are removed, so that if the {VRLinkedObject}
# is restored they will resume functioning normally.
# @param vrlos [Array] Array of unique keys of {VRLinkedObject}s that have been registered
# @return [Void]
def finalizeVRLinkedObjects(vrlos)
	toRemove = Array.new
	rts = RecordType.all(:isLinked => true)
	
	rts.each do |rt|
		if(!vrlos.include?(rt.linkedObjectKey))
			toRemove << rt.linkedObjectKey
		end
	end

	toRemove.each do |loKey|
		logputs "REMOVING VRLinkedObject (key: #{loKey}) because code file not registered"
		
		RecordType.all(:isLinked => true, :linkedObjectKey => loKey).each do |rt|
			rt.isLinked = false
			rt.save
		end
	end
end

##
# Given a number, return a string of the number properly formatted with commas
# @param n [Integer] Number to format with commas
# @return [String] Comma-formatted string representing the number
def formatCommas(n)
	return n.to_s.reverse.gsub(/...(?=.)/,'\&,').reverse
end

##
# Convert a Vulnerability Priority ENUM value (integer) to a String representing the priority
# @param level [Fixnum] the {VULN_PRIORITY} Enum value
# @param rtid [Integer] the ID of the RecordType to use for custom priority labels. Nil for default labels.
# @return [String] the String representing that priority
def vulnPriorityToString(level, rtid=nil)
	rt = nil
	rt = RecordType.get(rtid) unless rtid.nil?

	if(rtid.nil? || rt.nil?)
		return "Critical" if (level == VULN_PRIORITY::CRITICAL)
		return "High" if (level == VULN_PRIORITY::HIGH)
		return "Medium" if (level == VULN_PRIORITY::MEDIUM)
		return "Low" if (level == VULN_PRIORITY::LOW)
		return "Informational" if (level == VULN_PRIORITY::INFORMATIONAL)
		return "None"
	end

	return rt.getVulnPriorityString(level)
end

##
# Convert a {GEO} enum value (integer) to a String representing the geo
# @param geo [Fixnum] the {GEO} Enum value
# @return [String] the String representing that geo
def geoToString(geo)
	return "USA" if(geo == GEO::USA)
	return "North America" if(geo == GEO::NA)
	return "Central America" if(geo == GEO::CA)
	return "South America" if(geo == GEO::SA)
	return "Japan" if(geo == GEO::JP)
	return "China" if(geo == GEO::CN)
	return "APAC" if(geo == GEO::APAC)
	return "UK" if(geo == GEO::UK)
	return "EU" if(geo == GEO::EU)
	return "EMEA" if(geo == GEO::EMEA)
end

##
# Convert a {DASHPANEL_TYPE} enum value (integer) to a String representing the panel type
# @param pt [Fixnum] the {DASHPANEL_TYPE} Enum value
# @return [String] the String representing that panel type
def panelTypeToString(pt)
	return "My Active Reviews (All)" if (pt == DASHPANEL_TYPE::MYACTIVE)
	return "My Active Reviews (Type)" if (pt == DASHPANEL_TYPE::MYACTIVE_RT)
	return "My New Reviews (All)" if (pt == DASHPANEL_TYPE::MY_WNO_TESTS)
	return "My New Reviews (Type)" if (pt == DASHPANEL_TYPE::MY_WNO_TESTS_RT)
	return "In-Progress Reviews" if (pt == DASHPANEL_TYPE::STATUS_NEW_AND_INPROG)
	return "Passed Reviews" if (pt == DASHPANEL_TYPE::STATUS_PASSED)
	return "Failed Reviews" if (pt == DASHPANEL_TYPE::STATUS_FAILED)
	return "Closed Reviews" if (pt == DASHPANEL_TYPE::STATUS_CLOSED)
	return "All Reviews" if (pt == DASHPANEL_TYPE::ALL_APPS)
	return "New Reviews (No Tests)" if (pt == DASHPANEL_TYPE::APPS_WNO_TESTS)
	return "Unassigned New Reviews (All)" if (pt == DASHPANEL_TYPE::UNASSIGNED_NEW_ALL)
	return "Unassigned New Reviews (Type)" if (pt == DASHPANEL_TYPE::UNASSIGNED_NEW_RT)
	return "My Passed Reviews" if (pt == DASHPANEL_TYPE::MY_PASSED)
	return "My Failed Reviews" if (pt == DASHPANEL_TYPE::MY_FAILED)
	return "My Completed (All) Reviews" if (pt == DASHPANEL_TYPE::MY_ALL)
	return "Pending Approvals (All)" if (pt == DASHPANEL_TYPE::MY_APPROVALS)
	return "Pending Approvals (Type)" if (pt == DASHPANEL_TYPE::MY_APPROVALS_RT)

	return "UNK"
end

##
# Convert a SFDC 15-character (case sensitive) EID to an 18-char (API/case insensitive) EID
# Important because all API calls return 18-char EIDs (but can take 15 or 18 as input)
# so we need to make sure the EIDs we store/compare against are consistent
# @param id [String] 15-char EID
# @return [String] converted 18-char EID, or id if id is not 15 characters long
def idTo18(id)
	id = id.strip
	return id if(id.length != 15)

	map = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ012345'
	extra = ''

	id.scan(/.{5}/).each do |chunk|
		bits = []
		
		chunk.scan(/.{1}/).each do |char|
			bits.unshift( (char.to_i == 0 && char != 0 && char.downcase != char) ? 1 : 0)
		end
		
		ind = bits.inject(0) do |ind, bit|
			ind + ind + bit
		end

		extra += map[ind..ind]
	end

	return id + extra
end

##
# Generate the HTML for Test's export report
# @param tid [Integer] ID of Test to generate report for
# @return [String] HTML
def report_html(tid)
	@test = Test.get(tid)
	@app = @test.application
	
	rt = RecordType.get(@app.record_type)

	if(rt.exportFormat.nil? || rt.exportFormat == 0)
		f = File.open("exportTemplates/default.erb", "rb")
		renderer = ERB.new(f.read)
		return renderer.result(binding)
	else
		ef = ExportFormat.get(rt.exportFormat)
		f = ef.erb
		renderer = ERB.new(f)
		return renderer.result(binding)
	end
end

# Regular expression used to check if string is valid email
VALID_EMAIL_REGEX = /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z]+)*\.[a-z]+\z/i

##
# Check if string is a valid email address
#     Uses: VALID_EMAIL_REGEX = /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z]+)*\.[a-z]+\z/i
# @param e [String] String to check
# @return [Boolean] true if e is a valid email address, false otherwise
def isValidEmail?(e)
	return !(e =~ VALID_EMAIL_REGEX).nil?
end

##
# Given the records for a dash panel, count the total number of records including
# children (which would not be included by .size since children are nested
# within the parent element)
# @param records [Array<Hash>] Array of record hashes prepared for dashboard
# @return [Integer] Accurate size count including children
def getPanelRecordsCount(records)
	size = 0
	records.each do |rec|
		size += 1
		size += rec[:children].size if(!rec[:children].nil?)
	end

	return size
end

##
# Based on ENV variables, detect if Vulnreport is running on Heroku. This detection
# is based on the premise that a Heroku deploy will be using Heroku Postgres, resulting
# in the presence of an environment variable similar to HEROKU_POSTGRESQL_...
# @return [Boolean] True if running on Heroku, False otherwise
def onHeroku?()
	return ENV.any? {|x,_| x =~ /^HEROKU/ }
end
