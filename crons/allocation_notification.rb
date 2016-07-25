##
# Copyright (c) 2016, salesforce.com, inc.
# All rights reserved.
# Licensed under the BSD 3-Clause license. 
# For full license text, see LICENSE.txt file in the repo root  or https://opensource.org/licenses/BSD-3-Clause
##

require 'pony'
require 'active_support/core_ext/date_time/calculations'
require 'active_support/time'
require 'date'

##
# Notifies all {User}s marked as allocation users that they should set or confirm their allocation
# @cron Runs first of month at 7am
class AllocationNotification < VRCron
	vrcron_name :"Monthly Allocation Notification"
	vrcron_type :cron
	vrcron_schedule :"0 7 1 * *"

	##
	# Method invoked when called by the Scheduler job
	# @return [Boolean] Return is a pass-through of {notifyAll} - True on success, False otherwise
	def self.cron()
		return notifyAll()
	end

	##
	# For all {User}s marked as using allocation, notify that a {MonthlyAllocation} was automatically set or needs to be confirmed
	# This job should only run after {AllocationPreset} which will automatically set a {MonthlyAllocation} for that {User} if possible
	# @return [Boolean] True on success, False otherwise
	def self.notifyAll()
		users = User.all(:useAllocation => true, :active => true)

		users.each do |u|
			next if (!u.allocation.nil? && !u.allocation.wasAutoSet)

			@name = u.name.split(" ").first
			@autoset = !u.allocation.nil? && u.allocation.wasAutoSet
			if(u.allocation.nil?)
				@autosetAlloc = 0
			else
				@autosetAlloc = u.allocation.allocation
			end

			@vrurl = getSetting('VR_ROOT').to_s
			renderer = ERB.new(File.open("views/emails/allocEmail.erb", "rb").read)
			body = renderer.result(binding)
			
			recips = u.email

			fromEmail = getSetting('VR_NOREPLY_EMAIL')
			Pony.mail(:to => recips, :from => fromEmail, :subject => "Vulnreport Allocation for #{Date.today.strftime('%B')}", :html_body => body)
		end

		return true
	end
end