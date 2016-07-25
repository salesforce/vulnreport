##
# Copyright (c) 2016, salesforce.com, inc.
# All rights reserved.
# Licensed under the BSD 3-Clause license. 
# For full license text, see LICENSE.txt file in the repo root  or https://opensource.org/licenses/BSD-3-Clause
##

##
# VRCron is the parent class for all cronjobs tied into the Vulnreport system. By extending
# the VRCron class, cronjob classes will automatically be registered into the Vulnreport
# scheduler instance and run as part of the Vulnreport system (with access to the database
# and all other parts of Vulnreport).
#
# VRCron subclasses must define vrcron_name (a user-friendly and unique name for the cronjob), 
# vrcron_type of either :cron or :every, and vrcron_schedule with information when they should run.
# For instance, vrcron_type of :every and vrcron_schedule of 10m runs every 10 minutes. On the other hand,
# vrcron_type of :cron and vr_schedule of a crontab string '0 7 * * 1,3,5' runs MWF at 0700.
#
# VRCron subclasses must finally define a cron() method which is what will be invoked by the scheduler.
class VRCron
	class << self

		def inherited(cron)
			cronjobs << cron
		end

		def cronjobs
			@cronjobs ||= []
		end

		def vrcron_name(name=nil)
			@vrcron_name = name.to_s if !name.nil?
			@vrcron_name ||= self.name
		end

		def vrcron_type(type=nil)
			@vrcron_type = type if !type.nil?
			@vrcron_type ||= nil
		end

		def vrcron_schedule(sched=nil)
			@vrcron_schedule = sched.to_s if !sched.nil?
			@vrcron_schedule ||= nil
		end

		def each(&block)
			cronjobs.each do |member|
				block.call(member)
			end
		end

	end

	def cron
		raise "NotImplemented"
	end

	delegate :vrcron_name, to: :class
	delegate :vrcron_type, to: :class
	delegate :vrcron_schedule, to: :class
end