##
# Copyright (c) 2016, salesforce.com, inc.
# All rights reserved.
# Licensed under the BSD 3-Clause license. 
# For full license text, see LICENSE.txt file in the repo root  or https://opensource.org/licenses/BSD-3-Clause
##

class Vulnreport < Sinatra::Base
	##
	# Define a string to represent the action each monitor {EVENT_TYPE} is tracking
	# @param mt [Integer] From {AuditRecord}, the EVENT_TYPE
	# @return [String] String representation of event type that was recorded
	def getMonitorTypeString(mt)
		# Define this for all EVENT_TYPEs that are in MONITOR_EVENT_TYPES
		# See documentation on custom interfaces to learn more
	end

	##
	# Define a string to represent the action that caused the monitor {EVENT_TYPE} to be logged.
	# This string should be based on information in the {AuditRecord}
	# @param ma [AuditRecord]
	# @return [String] String representation of what caused this event to be recorded
	def getMonitorCausedByString(ma)
		# Define this for all EVENT_TYPEs that are in MONITOR_EVENT_TYPES
		# See documentation on custom interfaces to learn more
	end

	##
	# Get a string representing the actor/suspect action that caused an event to be recorded
	# @param ma [AuditRecord]
	# @return [String] String representation of who caused this event to be recorded
	def getMonitorSuspectString(ma)
		# Define this for all EVENT_TYPEs that are in MONITOR_EVENT_TYPES
		# See documentation on custom interfaces to learn more
	end

	##
	# Get a string representing the target that was modified/etc causing the event to be recorded
	# @param ma [AuditRecord]
	# @return [String] String representation of what the event recorded acted on
	def getMonitorTargetString(ma)
		# Define this for all EVENT_TYPEs that are in MONITOR_EVENT_TYPES
		# See documentation on custom interfaces to learn more
	end

	get '/auditMonitors/?' do
		halt 401, (erb :unauth) if(!canAuditMonitors?)

		if(MONITOR_EVENT_TYPES.size == 0)
			@noMonitorTypes = true
			@last = nil
			@next = nil
			@total = 0
			return erb :monitor_index
		end

		#Offset parse
		lim = 50

		if(params[:os].nil?)
			offset = 0
		else
			offset = params[:os].to_i
		end
		@total = AuditRecord.count(:event_type => MONITOR_EVENT_TYPES)

		@start = offset+1
		@end = (offset+lim > @total) ? @total : (offset+lim)

		@next = nil
		if(offset+lim < @total)
			@next = offset+lim
		end

		@last = nil
		if(offset > 0)
			@last = offset-lim
			if(@last < 0)
				@last = 0
			end
		end

		@mas = AuditRecord.all(:event_type => MONITOR_EVENT_TYPES, :order => [:event_at.desc], :limit => lim, :offset => offset)

		erb :monitor_index
	end

	post '/auditMonitors/:maid/markReviewed/?' do
		halt 401, (erb :unauth) if(!canAuditMonitors?)

		ma = AuditRecord.get(params[:maid].to_i)
		if(ma.nil?)
			return 404
		end

		ma.reviewed = true
		ma.reviewed_at = DateTime.now
		ma.reviewed_by = @session[:uid]
		if(ma.save)
			return 200
		else
			return 500
		end
	end

	post '/auditMonitors/:maid/reopen/?' do
		halt 401, (erb :unauth) if(!canAuditMonitors?)

		ma = AuditRecord.get(params[:maid].to_i)
		if(ma.nil?)
			return 404
		end

		ma.reviewed = false
		ma.flagged = false
		if(ma.save)
			return 200
		else
			return 500
		end
	end

	post '/auditMonitors/:maid/flag/?' do
		halt 401, (erb :unauth) if(!canAuditMonitors?)

		ma = AuditRecord.get(params[:maid].to_i)
		if(ma.nil?)
			return 404
		end

		ma.reviewed = true
		ma.flagged = true
		ma.reviewed_at = DateTime.now
		ma.reviewed_by = @session[:uid]
		if(ma.save)
			return 200
		else
			return 500
		end
	end

	get '/auditMonitors/:maid/markReviewed/?' do
		halt 401, (erb :unauth) if(!canAuditMonitors?)

		ma = AuditRecord.get(params[:maid].to_i)
		if(ma.nil?)
			return 404
		end

		ma.reviewed = true
		ma.reviewed_at = DateTime.now
		ma.reviewed_by = @session[:uid]
		if(ma.save)
			redirect "/auditMonitors/#{ma.id}"
		else
			Rollbar.error("Error saving AuditRecord object", {:monitorID => ma.id, :fault => ma.errors.to_s})
			@errstr = "Error marking AuditRecord as reviewed"
			erb :error
		end
	end

	get '/auditMonitors/:maid/reopen/?' do
		halt 401, (erb :unauth) if(!canAuditMonitors?)

		ma = AuditRecord.get(params[:maid].to_i)
		if(ma.nil?)
			return 404
		end

		ma.reviewed = false
		ma.flagged = false
		if(ma.save)
			redirect "/auditMonitors/#{ma.id}"
		else
			Rollbar.error("Error saving AuditRecord object", {:monitorID => ma.id, :fault => ma.errors.to_s})
			@errstr = "Error marking AuditRecord as reopened"
			erb :error
		end
	end

	get '/auditMonitors/:maid/flag/?' do
		halt 401, (erb :unauth) if(!canAuditMonitors?)

		ma = AuditRecord.get(params[:maid].to_i)
		if(ma.nil?)
			return 404
		end

		ma.reviewed = true
		ma.reviewed_at = DateTime.now
		ma.reviewed_by = @session[:uid]
		ma.flagged = true
		if(ma.save)
			redirect "/auditMonitors/#{ma.id}"
		else
			Rollbar.error("Error saving AuditRecord object", {:monitorID => ma.id, :fault => ma.errors.to_s})
			@errstr = "Error marking AuditRecord as flagged"
			erb :error
		end
	end

	get '/auditMonitors/:maid/?' do
		halt 401, (erb :unauth) if(!canAuditMonitors?)

		@ma = AuditRecord.get(params[:maid].to_i)
		if(@ma.nil?)
			@errstr = "Monitor Alert Not Found"
			erb :error
		end

		erb :monitor_alert_single
	end

	post '/auditMonitors/:maid/?' do
		halt 401, (erb :unauth) if(!canAuditMonitors?)

		@ma = AuditRecord.get(params[:maid].to_i)
		if(@ma.nil?)
			@errstr = "Monitor Alert Not Found"
			erb :error
		end

		redirect "/auditMonitors/#{@ma.id}"
	end

end