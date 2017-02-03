##
# Copyright (c) 2016, salesforce.com, inc.
# All rights reserved.
# Licensed under the BSD 3-Clause license. 
# For full license text, see LICENSE.txt file in the repo root  or https://opensource.org/licenses/BSD-3-Clause
##

class Vulnreport < Sinatra::Base
	########################
	# HELPERS
	########################
	
	##
	# Given the start date and end date in DateTime format, form a String representing the date period
	# to pass in the URL to a report. This method is used on the POST route to create a URL to call the
	# report via a GET route.
	# @param sd [DateTime] Start date of the period to report on
	# @param ed [DateTime] End date of the period to report on
	# @return [String] String representing reporting period e.g. "03-01-2016...04-01-2016"
	def form_datestring(sd, ed)
		if((sd.nil? || ed.empty?) && (sd.nil? || ed.empty?))
			return "all"
		else
			startdate = DateTime.strptime(sd, '%m-%d-%Y').strftime('%m-%d-%Y')
			enddate = DateTime.strptime(ed, '%m-%d-%Y').strftime('%m-%d-%Y')
			return "#{startdate}...#{enddate}"
		end
	end

	##
	# Given the Record Type params, form a string representing selected {RecordType}s to pass in the URL to
	# a report. This method is used on the POST route to create a URL to call the
	# report via a GET route. This method does NOT check permissions - see {#parseRt}
	# @param rt [String] Array of RecordType IDs
	# @param rtall [String] Value of the "all" report button representing all RTs
	# @return [String] String representing selected record types for the URL e.g. "all" or "1|3|4"
	def form_rtstring(rt, rtall)
		rtSelectAll = (!rtall.nil? && rtall.to_s.downcase == "all")
		if(rtSelectAll || rt.nil? || rt.empty?)
			rtStr = "all"
		else
			rtStr = rt.join("|")
		end

		return rtStr
	end

	##
	# Given the App Flags param, form a string representing selected flags to pass in the URL to
	# a report. This method is used on the POST route to create a URL to call the
	# report via a GET route.
	# @param f [String] the selected flags from the report filter multiselect
	# @param fall [String] Value of the "all" option from flag multiselect (DEPRECATED)
	# @return [String] String representing selected flags for the URL e.g. "all" or "1|3|4"
	def form_flagstring(f, fall)
		flagSelectAll = (!fall.nil? && fall.to_s.downcase == "all")
		if(flagSelectAll || f.nil? || f.empty?)
			flagStr = "all"
		else
			flagStr = f.join("|")
		end

		return flagStr
	end

	##
	# Parse the date period for a report given in report URL (formed by {#form_datestring})
	# @param period [String] Period string formed by form_datestring, e.g. "03-01-2016...04-01-2016"
	# @param defaultStart [DateTime] default start date to use if period is "default"
	# @param defaultEnd [DateTime] default end date to use if period is "default"
	# @return [DateTime,DateTime,String] start date (DateTime), end date (DateTime), and string representing the period for the UI (String)
	def parsePeriod(period, defaultStart = nil, defaultEnd = nil)
		startdate = nil
		enddate = nil
		periodString = nil

		if(period == "default")
			startdate = (defaultStart.nil?) ? Date.today.at_beginning_of_month.prev_month.to_datetime : defaultStart
			enddate = (defaultEnd.nil?) ?  Date.today.to_datetime.end_of_day : defaultEnd
			periodString = startdate.strftime('%m-%d-%Y') + " to " + enddate.strftime('%m-%d-%Y')
		elsif(period == "all")
			startdate = DateTime.strptime("01-01-2012", '%m-%d-%Y')
			enddate = Date.today.to_datetime+1
			periodString = "All"
		else
			startdate = DateTime.strptime(period.split("...")[0], '%m-%d-%Y')
			enddate = DateTime.strptime(period.split("...")[1], '%m-%d-%Y').end_of_day
			periodString = startdate.strftime('%m-%d-%Y') + " to " + enddate.strftime('%m-%d-%Y')
		end

		return startdate, enddate, periodString
	end

	##
	# Parse the reporting interval for a report given in report URL
	# @param param [String] The interval parameter
	# @param allowed [Array<String>] Allowed intervals
	# @param default [String] Default interval to use if param is invalid
	# @return [String, String] The parsed parameter, Capitalized interval for UI
	def parseInterval(param, allowed, default="month")
		param = default unless allowed.map{|i| i.downcase}.include?(param)
		
		return param, param.capitalize
	end

	##
	# Parse the app flags parameter given in report URL (formed by {#form_flagstring})
	# @param param [String] Flags chosen string formed by form_flagstring
	# @return [Hash{String => Boolean}, String] Hash with keys of flags to boolean representing selection,
	# @return [Array<Integer>, String] Array of integers representing selected {Flag}s (IDs) and String of chosen flags for UI
	def parseFlags(param)
		if(param.nil? || param.downcase == "all")
			selectedFlags = [-1]
			uiStr = "all"
		else
			selectedFlags = param.split("|").map{|n| n.to_i}
			uiStr = "flagged"
		end

		return selectedFlags, uiStr
	end

	##
	# Parse the Record Types parameter given in report URL (formed by {#form_rtstring}) and 
	# validate user permission to access those {RecordType}s
	# @param param [String] Record Types chosen string formed by form_rtstring e.g. 1|3|4
	# @param default [Array<Integer>] Default selection (array of {RecordType} IDs). 
	#  Used if param is "default" or if none of selected RecordTypes are accessible to user
	# @return [Array<Integer>] Array of integers representing selected {RecordType}s (IDs)
	def parseRt(param, default=nil)
		allowedRecordTypes = getAllowedRTsForUser(@session[:uid])
		if(!default.nil?)
			default = allowedRecordTypes & default
		end

		if(param.nil? || param.downcase == "all")
			selectedRecordTypes = allowedRecordTypes
		elsif(param.downcase == "default")
			selectedRecordTypes = (default.nil?) ? allowedRecordTypes : default
		else
			selectedRecordTypes = allowedRecordTypes & (param.split("|").map{|n| n.to_i})
		end

		if(selectedRecordTypes.nil? || selectedRecordTypes.size == 0)
			return (default.nil?) ? allowedRecordTypes : default
		else
			return selectedRecordTypes
		end
	end

	##
	# Given date, return start of FY quarter it falls in
	# @param d [DateTime] Date to find quarter for
	# @return [Date] First day of FY quarter that d falls in
	def startOfQuarter(d)
		d = d.to_date
		if(d.month >= 2 && d.month <= 4)
			return Date.new(d.year, 2, 1)
		elsif(d.month >= 5 && d.month <= 7)
			return Date.new(d.year, 5, 1)
		elsif(d.month >= 8 && d.month <= 10)
			return Date.new(d.year, 8, 1)
		elsif(d.month == 11 || d.month == 12)
			return Date.new(d.year, 11, 1)
		elsif(d.month == 1)
			return Date.new((d.year-1), 11, 1)
		end
	end

	##
	# Given date, return end of FY quarter it falls in
	# @param d [DateTime] Date to find quarter for
	# @return [Date] Last day of FY quarter that d falls in
	def endOfQuarter(d)
		d = d.to_date
		if(d.month >= 2 && d.month <= 4)
			return Date.new(d.year, 4, 30)
		elsif(d.month >= 5 && d.month <= 7)
			return Date.new(d.year, 7, 31)
		elsif(d.month >= 8 && d.month <= 10)
			return Date.new(d.year, 10, 31)
		elsif(d.month == 11 || d.month == 12)
			return Date.new((d.year+1), 1, 31)
		elsif(d.month == 1)
			return Date.new(d.year, 1, 31)
		end
	end

	##
	# Given date, return number of FY quarter it falls in
	# @param d [DateTime] Date to find quarter for
	# @return [Integer] FY Q number
	def qnum(d)
		d = d.to_date
		if(d.month >= 2 && d.month <= 4)
			return 1
		elsif(d.month >= 5 && d.month <= 7)
			return 2
		elsif(d.month >= 8 && d.month <= 10)
			return 3
		else
			return 4
		end
	end

	##
	# Given date, return FY it falls in
	# @param d [DateTime] Date to find FY for
	# @return [Integer] FY number
	def fy(d)
		d = d.to_date
		if(d.month >= 2)
			return (d.year+1)
		else
			return d.year
		end
	end

	#################################
	# Approval Flow Disagreements 	#
	#################################

	get '/reports/tests/disagreements/:period/:flags/?' do
		@formsub = "/reports/tests/disagreements"

		@startdate, @enddate, @periodString = parsePeriod(params[:period].downcase)
		@selectedFlags, @appTypeString = parseFlags(params[:flags])

		@matches = Array.new
		Test.allWithFlags(@selectedFlags, :pending_at.not => nil, :complete => true, :closed_at => (@startdate..@enddate)).each do |t|
			if(t.pending_pass != t.pass)
				@matches << t
			end
		end

		erb :"reports/disagreements"
	end

	post '/reports/tests/disagreements/?' do
		datestring = (params[:alldata]) ? "all" : form_datestring(params[:startdate], params[:enddate])
		flags = form_flagstring(params[:appFlags], params[:flagSelectAll])	
		redirect "/reports/tests/disagreements/#{datestring}/#{flags}"
	end

	get '/reports/tests/disagreements/?' do
		redirect "/reports/tests/disagreements/default/all"
	end

	####################################
	# Approval Flow Disagreements/Time #
	####################################

	get '/reports/tests/disagreementsOverTime/:period/:interval/:flags/?' do
		@formsub = "/reports/tests/disagreementsOverTime"
		@intervals = ["Day", "Week", "Month", "Quarter", "Year"]
		
		@int, @intString = parseInterval(params[:interval].downcase, @intervals)
		@startdate, @enddate, @periodString = parsePeriod(params[:period].downcase)
		@selectedFlags, @appTypeString = parseFlags(params[:flags])

		@labels = Array.new
		@counts = Array.new
		@matches = Array.new
		if(@int == "day")
			@startdate.upto(@enddate) do |date|
				count = 0
				@labels << date.strftime('%m-%d-%Y')
				Test.allWithFlags(@selectedFlags, :pending_at.not => nil, :complete => true, :closed_at => date).each do |t|
					if(t.pending_pass != t.pass)
						count += 1
						@matches << t
					end
				end
				@counts << count
			end
		elsif(@int == "week")
			@startdate.step(@enddate, 7) do |date|
				count = 0
				@labels << date.strftime('%m-%d-%Y')
				Test.allWithFlags(@selectedFlags, :pending_at.not => nil, :complete => true, :closed_at => (date..date+7)).each do |t|
					if(t.pending_pass != t.pass)
						count += 1
						@matches << t
					end
				end
				@counts << count
			end
		elsif(@int == "month")
			date = Date.new(@startdate.year, @startdate.month, 1)
			while date < @enddate do
				count = 0
				@labels << date.strftime('%B, %Y')
				Test.allWithFlags(@selectedFlags, :pending_at.not => nil, :complete => true, :closed_at => (date.to_datetime.beginning_of_day..(date.end_of_month.to_datetime.end_of_day))).each do |t|
					if(t.pending_pass != t.pass)
						count += 1
						@matches << t
					end
				end
				@counts << count
				date = (date >> 1)
			end
		elsif(@int == "quarter")
			first = (startOfQuarter(@startdate) < @startdate) ? @startdate : startOfQuarter(@startdate)
			last = (endOfQuarter(@startdate) > @enddate) ? @enddate : endOfQuarter(@startdate)
			while first < @enddate do
				count = 0
				@labels << "Q" + qnum(first).to_s + ", FY " + fy(first).to_s
				Test.allWithFlags(@selectedFlags, :pending_at.not => nil, :complete => true, :closed_at => ((first.to_datetime)...(last.to_datetime.end_of_day))).each do |t|
					if(t.pending_pass != t.pass)
						count += 1
						@matches << t
					end
				end
				@counts << count
				first = startOfQuarter(first >> 3)
				last = (endOfQuarter(first) > @enddate) ? @enddate : endOfQuarter(first)
			end
		elsif(@int == "year")
			first = @startdate.to_date
			last = Date.new(first.year, 12, 31)
			last = @enddate if @enddate < last
			while first < @enddate do
				count = 0
				@labels << first.strftime('%Y')
				Test.allWithFlags(@selectedFlags, :pending_at.not => nil, :complete => true, :closed_at => ((first.to_datetime)...(last.to_datetime.end_of_day))).each do |t|
					if(t.pending_pass != t.pass)
						count += 1
						@matches << t
					end
				end
				@counts << count
				first = Date.new((first.year+1), 1, 1)
				last = Date.new(first.year, 12, 31)
				last = @enddate.to_date if @enddate < last
			end
		end

		erb :"reports/disagreementsOverTime"
	end

	post '/reports/tests/disagreementsOverTime/?' do
		datestring = (params[:alldata]) ? "all" : form_datestring(params[:startdate], params[:enddate])
		int = params[:interval]
		flags = form_flagstring(params[:appFlags], params[:flagSelectAll])
		redirect "/reports/tests/disagreementsOverTime/#{datestring}/#{int}/#{flags}"
	end

	get '/reports/tests/disagreementsOverTime/?' do
		redirect "/reports/tests/disagreementsOverTime/default/month/all"
	end

	############################
	# Test Times to Completion #
	############################

	get '/reports/tests/testTimes/:period/:interval/:flags/:rt/?' do
		@formsub = "/reports/tests/testTimes"
		@intervals = ["Month", "Quarter", "Year"]
		
		@int, @intString = parseInterval(params[:interval].downcase, @intervals)
		@selectedFlags, @appTypeString = parseFlags(params[:flags])
		@startdate, @enddate, @periodString = parsePeriod(params[:period].downcase)
		@selectedRecordTypes = parseRt(params[:rt])

		@labels = Array.new
		@counts = Array.new
		@conCounts = Array.new
		@approvalCounts = Array.new
		@matches = Array.new

		dr_internalDays = 0
		dr_conDays = 0
		dr_conApproveDays = 0
		dr_internalNumTests = 0
		dr_conNumTests = 0

		if(@int == "month")
			date = Date.new(@startdate.year, @startdate.month, 1)
			while date < @enddate do
				@labels << date.strftime('%B, %Y')

				totalDays = 0
				conTotalDays = 0
				totalTests = 0
				conTotalTests = 0
				totalDaysToApprove = 0
				Test.allWithFlags(@selectedFlags, :complete => true, :closed_at => (date..(date.end_of_month).to_datetime.end_of_day), Test.application.record_type => @selectedRecordTypes).each do |t|
					t.con_closed_at = t.closed_at if t.con_closed_at.nil?

					if(t.contractor_test)
						conTotalDays += t.closed_at - t.created_at
						totalDaysToApprove += t.closed_at - t.con_closed_at
						conTotalTests += 1
					else
						totalDays += t.closed_at - t.created_at
						totalTests += 1					
					end
				end
				dr_internalDays += totalDays
				dr_conDays += conTotalDays
				dr_conApproveDays += totalDaysToApprove
				dr_internalNumTests += totalTests
				dr_conNumTests += conTotalTests

				@counts << ((totalTests == 0) ? 0.0 : (totalDays.to_f/totalTests.to_f).round(2))
				@conCounts << ((conTotalTests == 0) ? 0.0 : (conTotalDays.to_f/conTotalTests.to_f).round(2))
				@approvalCounts << ((conTotalTests == 0) ? 0.0 : (totalDaysToApprove.to_f/conTotalTests.to_f).round(2))

				date = (date >> 1)
			end
		elsif(@int == "quarter")
			first = (startOfQuarter(@startdate) < @startdate) ? @startdate : startOfQuarter(@startdate)
			last = (endOfQuarter(@startdate) > @enddate) ? @enddate : endOfQuarter(@startdate)
			while first < @enddate do
				@labels << "Q" + qnum(first).to_s + ", FY " + fy(first).to_s
				
				totalDays = 0
				conTotalDays = 0
				totalTests = 0
				conTotalTests = 0
				totalDaysToApprove = 0
				Test.allWithFlags(@selectedFlags, :complete => true, :closed_at => ((first.to_datetime)...(last.to_datetime.end_of_day)), Test.application.record_type => @selectedRecordTypes).each do |t|
					t.con_closed_at = t.closed_at if t.con_closed_at.nil?

					if(t.contractor_test)
						conTotalDays += t.closed_at - t.created_at
						totalDaysToApprove += t.closed_at - t.con_closed_at
						conTotalTests += 1
					else
						totalDays += t.closed_at - t.created_at
						totalTests += 1					
					end
				end
				dr_internalDays += totalDays
				dr_conDays += conTotalDays
				dr_conApproveDays += totalDaysToApprove
				dr_internalNumTests += totalTests
				dr_conNumTests += conTotalTests

				@counts << ((totalTests == 0) ? 0.0 : (totalDays.to_f/totalTests.to_f).round(2))
				@conCounts << ((conTotalTests == 0) ? 0.0 : (conTotalDays.to_f/conTotalTests.to_f).round(2))
				@approvalCounts << ((conTotalTests == 0) ? 0.0 : (totalDaysToApprove.to_f/conTotalTests.to_f).round(2))

				first = startOfQuarter(first >> 3)
				last = (endOfQuarter(first) > @enddate) ? @enddate : endOfQuarter(first)
			end
		elsif(@int == "year")
			first = @startdate.to_date
			last = Date.new(first.year, 12, 31)
			last = @enddate if @enddate < last
			while first < @enddate do
				@labels << first.strftime('%Y')
				
				totalDays = 0
				conTotalDays = 0
				totalTests = 0
				conTotalTests = 0
				totalDaysToApprove = 0
				Test.allWithFlags(@selectedFlags, :complete => true, :closed_at => ((first.to_datetime)...(last.to_datetime.end_of_day)), Test.application.record_type => @selectedRecordTypes).each do |t|
					t.con_closed_at = t.closed_at if t.con_closed_at.nil?

					if(t.contractor_test)
						conTotalDays += t.closed_at - t.created_at
						totalDaysToApprove += t.closed_at - t.con_closed_at
						conTotalTests += 1
					else
						totalDays += t.closed_at - t.created_at
						totalTests += 1					
					end
				end
				dr_internalDays += totalDays
				dr_conDays += conTotalDays
				dr_conApproveDays += totalDaysToApprove
				dr_internalNumTests += totalTests
				dr_conNumTests += conTotalTests

				@counts << ((totalTests == 0) ? 0.0 : (totalDays.to_f/totalTests.to_f).round(2))
				@conCounts << ((conTotalTests == 0) ? 0.0 : (conTotalDays.to_f/conTotalTests.to_f).round(2))
				@approvalCounts << ((conTotalTests == 0) ? 0.0 : (totalDaysToApprove.to_f/conTotalTests.to_f).round(2))

				first = Date.new((first.year+1), 1, 1)
				last = Date.new(first.year, 12, 31)
				last = @enddate.to_date if @enddate < last
			end
		end

		@dr_internalAvgDays = ((dr_internalNumTests == 0) ? 0.0 : (dr_internalDays.to_f/dr_internalNumTests.to_f).round(2))
		@dr_conAvgDays = ((dr_conNumTests == 0) ? 0.0 : (dr_conDays.to_f/dr_conNumTests.to_f).round(2))
		@dr_approvalAvgDays = ((dr_conNumTests == 0) ? 0.0 : (dr_conApproveDays.to_f/dr_conNumTests.to_f).round(2))

		erb :"reports/testTimes"
	end

	post '/reports/tests/testTimes/?' do
		datestring = (params[:alldata]) ? "all" : form_datestring(params[:startdate], params[:enddate])
		int = params[:interval]
		flags = form_flagstring(params[:appFlags], params[:flagSelectAll])
		rtStr = form_rtstring(params[:recordTypes], params[:rtSelectAll])
		
		redirect "/reports/tests/testTimes/#{datestring}/#{int}/#{flags}/#{rtStr}"
	end

	get '/reports/tests/testTimes/?' do
		redirect "/reports/tests/testTimes/default/month/all/all"
	end

	#################################
	# Total Time to Test Resolution #
	#################################

	get '/reports/tests/ttr/:period/:interval/:flags/:rt/?' do
		@formsub = "/reports/tests/ttr"
		@intervals = ["Month", "Quarter", "Year"]

		@int, @intString = parseInterval(params[:interval].downcase, @intervals)
		@selectedFlags, @appTypeString = parseFlags(params[:flags])
		@startdate, @enddate, @periodString = parsePeriod(params[:period].downcase)
		@selectedRecordTypes = parseRt(params[:rt])

		@labels = Array.new
		@counts = Array.new
		@maxes = Array.new
		@maxTests = Array.new
		@mins = Array.new
		@minTests = Array.new
		@numTests = Array.new
		if(@int == "month")
			date = Date.new(@startdate.year, @startdate.month, 1)
			while date < @enddate do
				@labels << date.strftime('%B, %Y')

				totalDays = 0.0
				totalTests = 0
				max = 0.0
				maxtest = nil
				min = 0.0
				mintest = nil
				Test.allWithFlags(@selectedFlags, :complete => true, :closed_at => (date.to_datetime.beginning_of_day..(date.end_of_month.to_datetime.end_of_day)), Test.application.record_type => @selectedRecordTypes).each do |t|
					testTimeDays = (t.closed_at - t.created_at).to_f

					if(testTimeDays > max)
						max = testTimeDays
						maxtest = t
					end

					if(testTimeDays < min || min == 0.0)
						min = testTimeDays
						mintest = t
					end

					totalDays += testTimeDays
					totalTests += 1
				end
				@counts << ((totalTests == 0) ? 0.0 : (totalDays/totalTests.to_f))
				@maxes << max
				@maxTests << maxtest
				@mins << min
				@minTests << mintest
				@numTests << totalTests
				
				date = (date >> 1)
			end
		elsif(@int == "quarter")
			first = (startOfQuarter(@startdate) < @startdate) ? @startdate : startOfQuarter(@startdate)
			last = (endOfQuarter(@startdate) > @enddate) ? @enddate : endOfQuarter(@startdate)
			while first < @enddate do
				@labels << "Q" + qnum(first).to_s + ", FY " + fy(first).to_s
				
				totalDays = 0.0
				totalTests = 0
				max = 0.0
				maxtest = nil
				min = 0.0
				mintest = nil
				Test.allWithFlags(@selectedFlags, :complete => true, :closed_at => ((first.to_datetime)...(last.to_datetime.end_of_day)), Test.application.record_type => @selectedRecordTypes).each do |t|
					testTimeDays = (t.closed_at - t.created_at).to_f

					if(testTimeDays > max)
						max = testTimeDays
						maxtest = t
					end

					if(testTimeDays < min || min == 0.0)
						min = testTimeDays
						mintest = t
					end

					totalDays += testTimeDays
					totalTests += 1
				end
				@counts << ((totalTests == 0) ? 0.0 : (totalDays/totalTests.to_f))
				@maxes << max
				@maxTests << maxtest
				@mins << min
				@minTests << mintest
				@numTests << totalTests

				first = startOfQuarter(first >> 3)
				last = (endOfQuarter(first) > @enddate) ? @enddate : endOfQuarter(first)
			end
		elsif(@int == "year")
			first = @startdate.to_date
			last = Date.new(first.year, 12, 31)
			last = @enddate if @enddate < last
			while first < @enddate do
				@labels << first.strftime('%Y')
				
				totalDays = 0.0
				totalTests = 0
				max = 0.0
				maxtest = nil
				min = 0.0
				mintest = nil
				Test.allWithFlags(@selectedFlags, :complete => true, :closed_at => ((first.to_datetime)...(last.to_datetime.end_of_day)), Test.application.record_type => @selectedRecordTypes).each do |t|
					testTimeDays = (t.closed_at - t.created_at).to_f

					if(testTimeDays > max)
						max = testTimeDays
						maxtest = t
					end

					if(testTimeDays < min || min == 0.0)
						min = testTimeDays
						mintest = t
					end

					totalDays += testTimeDays
					totalTests += 1
				end
				@counts << ((totalTests == 0) ? 0.0 : (totalDays/totalTests.to_f))
				@maxes << max
				@maxTests << maxtest
				@mins << min
				@minTests << mintest
				@numTests << totalTests

				first = Date.new((first.year+1), 1, 1)
				last = Date.new(first.year, 12, 31)
				last = @enddate.to_date if @enddate < last
			end
		end

		@totalTests = @numTests.inject(0, :+)
		@avgTTR = 0
		num = 0
		denom = 0
		@counts.each_with_index do |c, i|
			num += c*@numTests[i]
			denom += @numTests[i]
		end

		if(denom > 0)
			@avgTTR = (num/denom)
		end

		erb :"reports/timeToResolution"
	end

	post '/reports/tests/ttr/?' do
		datestring = (params[:alldata]) ? "all" : form_datestring(params[:startdate], params[:enddate])
		int = params[:interval]
		flags = form_flagstring(params[:appFlags], params[:flagSelectAll])
		rtStr = form_rtstring(params[:recordTypes], params[:rtSelectAll])
		
		redirect "/reports/tests/ttr/#{datestring}/#{int}/#{flags}/#{rtStr}"
	end

	get '/reports/tests/ttr/?' do
		redirect "/reports/tests/ttr/default/month/all/all"
	end

	#################
	# Tests to Pass #
	#################

	get '/reports/tests/testsToPass/:period/:interval/:flags/:rt/?' do
		@formsub = "/reports/tests/testsToPass"
		@intervals = ["Month", "Quarter", "Year"]

		@int, @intString = parseInterval(params[:interval].downcase, @intervals)
		@selectedFlags, @appTypeString = parseFlags(params[:flags])
		@startdate, @enddate, @periodString = parsePeriod(params[:period].downcase)
		@selectedRecordTypes = parseRt(params[:rt])

		@labels = Array.new
		@counts = Array.new
		@maxes = Array.new
		@maxApps = Array.new
		@mins = Array.new
		@minApps = Array.new
		@apps = Array.new
		@tests = Array.new
		if(@int == "month")
			date = Date.new(@startdate.year, @startdate.month, 1)
			while date < @enddate do
				@labels << date.strftime('%B, %Y')

				total = 0
				totalApps = 0
				max = 0
				maxapp = nil
				min = 0
				minapp = nil

				tests = Test.allWithFlags(@selectedFlags, :fields => [:application_id], :unique => true, Test.application.record_type => @selectedRecordTypes, :complete => true, :pass => true, :closed_at => (date..(date.end_of_month).to_datetime.end_of_day), :order => [:application_id.asc])

				tests.each do |t|
					aid = t.application_id
					tests = Test.all(:application_id => aid)

					numPasses = 0
					ttp = 0

					tests.each do |t|
						if(t.pass)
							numPasses += 1
						end
					end

					if(numPasses == 1)
						ttp = tests.size
					else
						ttp = 1
						tests.reverse.drop(1).each do |t|
							if(!t.pass)
								ttp += 1
							else
								break
							end
						end
					end

					total += ttp
					totalApps += 1

					if(ttp > max)
						max = ttp
						maxapp = Application.get(aid)
					end

					if(ttp < min || min == 0)
						min = ttp
						minapp = Application.get(aid)
					end
				end
				
				@counts << ((totalApps == 0) ? 0 : (total.to_f/totalApps.to_f).round(3))
				@maxes << max
				@maxApps << maxapp
				@mins << min
				@minApps << minapp
				@apps << totalApps
				@tests << total
				
				date = (date >> 1)
			end
		elsif(@int == "quarter")
			first = (startOfQuarter(@startdate) < @startdate) ? @startdate : startOfQuarter(@startdate)
			last = (endOfQuarter(@startdate) > @enddate) ? @enddate : endOfQuarter(@startdate)
			while first < @enddate do
				@labels << "Q" + qnum(first).to_s + ", FY " + fy(first).to_s
				
				total = 0
				totalApps = 0
				max = 0
				maxapp = nil
				min = 0
				minapp = nil
				
				tests = Test.allWithFlags(@selectedFlags, :fields => [:application_id], :unique => true, Test.application.record_type => @selectedRecordTypes, :complete => true, :pass => true, :closed_at => (first.to_datetime..(last.to_datetime.end_of_day)), :order => [:application_id.asc])

				tests.each do |t|
					aid = t.application_id
					tests = Test.all(:application_id => aid)

					numPasses = 0
					ttp = 0

					tests.each do |t|
						if(t.pass)
							numPasses += 1
						end
					end

					if(numPasses == 1)
						ttp = tests.size
					else
						ttp = 1
						tests.reverse.drop(1).each do |t|
							if(!t.pass)
								ttp += 1
							else
								break
							end
						end
					end

					total += ttp
					totalApps += 1

					if(ttp > max)
						max = ttp
						maxapp = Application.get(aid)
					end

					if(ttp < min || min == 0)
						min = ttp
						minapp = Application.get(aid)
					end
				end

				@counts << ((totalApps == 0) ? 0 : (total.to_f/totalApps.to_f).round(3))
				@maxes << max
				@maxApps << maxapp
				@mins << min
				@minApps << minapp
				@apps << totalApps
				@tests << total

				first = startOfQuarter(first >> 3)
				last = (endOfQuarter(first) > @enddate) ? @enddate : endOfQuarter(first)
			end
		elsif(@int == "year")
			first = @startdate.to_date
			last = Date.new(first.year, 12, 31)
			last = @enddate if @enddate < last
			while first < @enddate do
				@labels << first.strftime('%Y')
				
				total = 0
				totalApps = 0
				max = 0
				maxapp = nil
				min = 0
				minapp = nil
				
				tests = Test.allWithFlags(@selectedFlags, :fields => [:application_id], :unique => true, Test.application.record_type => @selectedRecordTypes, :complete => true, :pass => true, :closed_at => (first.to_datetime..(last.to_datetime.end_of_day)), :order => [:application_id.asc])

				tests.each do |t|
					aid = t.application_id
					tests = Test.all(:application_id => aid)

					numPasses = 0
					ttp = 0

					tests.each do |t|
						if(t.pass)
							numPasses += 1
						end
					end

					if(numPasses == 1)
						ttp = tests.size
					else
						ttp = 1
						tests.reverse.drop(1).each do |t|
							if(!t.pass)
								ttp += 1
							else
								break
							end
						end
					end

					total += ttp
					totalApps += 1

					if(ttp > max)
						max = ttp
						maxapp = Application.get(aid)
					end

					if(ttp < min || min == 0)
						min = ttp
						minapp = Application.get(aid)
					end
				end

				@counts << ((totalApps == 0) ? 0 : (total.to_f/totalApps.to_f).round(3))
				@maxes << max
				@maxApps << maxapp
				@mins << min
				@minApps << minapp
				@apps << totalApps
				@tests << total

				first = Date.new((first.year+1), 1, 1)
				last = Date.new(first.year, 12, 31)
				last = @enddate.to_date if @enddate < last
			end
		end

		@totalApps = @apps.inject(0, :+)
		@totalTests = @tests.inject(0, :+)

		erb :"reports/testsToPass"
	end

	post '/reports/tests/testsToPass/?' do
		datestring = (params[:alldata]) ? "all" : form_datestring(params[:startdate], params[:enddate])
		int = params[:interval]		
		flags = form_flagstring(params[:appFlags], params[:flagSelectAll])
		rtStr = form_rtstring(params[:recordTypes], params[:rtSelectAll])

		redirect "/reports/tests/testsToPass/#{datestring}/#{int}/#{flags}/#{rtStr}"
	end

	get '/reports/tests/testsToPass/?' do
		redirect "/reports/tests/testsToPass/default/month/all/all"
	end

	#################
	# Vulns By Type #
	#################

	get '/reports/vulns/VulnsByType/:period/:flags/:rt/?' do
		@formsub = "/reports/vulns/VulnsByType"

		@startdate, @enddate, @periodString = parsePeriod(params[:period].downcase)
		@selectedFlags, @appTypeString = parseFlags(params[:flags])
		@selectedRecordTypes = parseRt(params[:rt])

		@labels = Array.new
		@counts = Array.new
		Vulnerability.allWithFlags(@selectedFlags, :created_at => (@startdate..@enddate), :verified => true, :falsepos => false, Vulnerability.test.application.record_type => @selectedRecordTypes).each do |v|
			if(v.vulntype == 0)
				thisLabel = "Custom / Other"
			else
				thisLabel = v.type_str
			end

			idx = @labels.index(thisLabel)
			if(idx.nil?)
				@labels << thisLabel
				@counts << 1
			else
				@counts[idx] += 1
			end
		end

		@totalVulns = @counts.inject(0, :+)

		erb :"reports/vulnsbytype"
	end

	post '/reports/vulns/VulnsByType/?' do
		datestring = (params[:alldata]) ? "all" : form_datestring(params[:startdate], params[:enddate])		
		flags = form_flagstring(params[:appFlags], params[:flagSelectAll])
		rtStr = form_rtstring(params[:recordTypes], params[:rtSelectAll])

		redirect "/reports/vulns/VulnsByType/#{datestring}/#{flags}/#{rtStr}"
	end

	get '/reports/vulns/VulnsByType/?' do
		redirect "/reports/vulns/VulnsByType/default/all/all"
	end

	###################
	# Vulns By Source #
	###################

	get '/reports/vulns/vulnsBySource/:period/:flags/:rt/?' do
		@formsub = "/reports/vulns/vulnsBySource"

		@startdate, @enddate, @periodString = parsePeriod(params[:period].downcase)
		@selectedFlags, @appTypeString = parseFlags(params[:flags])
		@selectedRecordTypes = parseRt(params[:rt])

		colors = [[151,187,205],[200,200,200],[0,0,255],[0,128,0],[0,255,255],[128,0,0],[255,0,0],[190,190,0],[255,0,255],[128,128,0],[128,128,128]]
		coloridx = 0

		@data = Hash.new
		Vulnerability.allWithFlags(@selectedFlags, :created_at => (@startdate..@enddate), :verified => true, :falsepos => false, Vulnerability.test.application.record_type => @selectedRecordTypes).each do |v|
			if(@data[v.vulnSource].nil?)
				if(v.vulnSource == 0)
					thisLabel = "Manual Testing"
				else
					thisLabel = v.source_string
				end

				thisColor = colors[coloridx]
				coloridx += 1
				coloridx = 0 if(coloridx > colors.size)

				@data[v.vulnSource] = {:label => thisLabel, :count => 1, :color => "rgba(#{thisColor[0]},#{thisColor[1]},#{thisColor[2]},1)"}
			else
				@data[v.vulnSource][:count] += 1
			end
		end

		@totalVulns = @data.keys.inject(0){|sum, id| sum + @data[id][:count]}

		erb :"reports/vulnsBySource"
	end

	post '/reports/vulns/vulnsBySource/?' do
		datestring = (params[:alldata]) ? "all" : form_datestring(params[:startdate], params[:enddate])		
		flags = form_flagstring(params[:appFlags], params[:flagSelectAll])
		rtStr = form_rtstring(params[:recordTypes], params[:rtSelectAll])

		redirect "/reports/vulns/vulnsBySource/#{datestring}/#{flags}/#{rtStr}"
	end

	get '/reports/vulns/vulnsBySource/?' do
		redirect "/reports/vulns/vulnsBySource/default/all/all"
	end

	#############################
	# Vulnerabilities Over Time #
	#############################

	get '/reports/vulns/vulnerabilitiesOverTime/:period/:interval/:flags/:rt/?' do
		@formsub = "/reports/vulns/vulnerabilitiesOverTime"
		@intervals = ["Day", "Week", "Month", "Quarter", "Year"]

		@int, @intString = parseInterval(params[:interval].downcase, @intervals)
		@startdate, @enddate, @periodString = parsePeriod(params[:period].downcase)
		@selectedFlags, @appTypeString = parseFlags(params[:flags])
		@selectedRecordTypes = parseRt(params[:rt])
		
		@datasets = Hash.new
		@datasets["All"] = Array.new
		@datasets["Custom/Other"] = Array.new
		VulnType.all().each do |vt|
			@datasets[vt.name] = Array.new
		end
		@labels = Array.new

		if(@int == "day")
			@startdate.upto(@enddate) do |date|
				@labels << date.strftime('%m-%d-%Y')
				allcount = 0
				
				@datasets.keys.each do |key|
					next if(key.downcase == "all" || key.downcase == "custom/other")
					vt = VulnType.getTypeByName(key)
					ct = Vulnerability.countWithFlags(@selectedFlags, :vulntype => vt.id, :verified => true, :falsepos => false, Vulnerability.test.application.record_type => @selectedRecordTypes, :created_at => (date...(date+1)))
					@datasets[key] << ct
					allcount += ct
				end
				
				otherCt = Vulnerability.countWithFlags(@selectedFlags, :vulntype => 0, :verified => true, :falsepos => false, Vulnerability.test.application.record_type => @selectedRecordTypes, :created_at => (date...(date+1)))
				
				@datasets["Custom/Other"] << otherCt
				allcount += otherCt

				@datasets["All"] << allcount
			end
		elsif(@int == "week")
			@startdate.step(@enddate, 7) do |date|
				@labels << date.strftime('%m-%d-%Y')
				allcount = 0
				
				@datasets.keys.each do |key|
					next if(key.downcase == "all" || key.downcase == "custom/other")
					vt = VulnType.getTypeByName(key)
					ct = Vulnerability.countWithFlags(@selectedFlags, :vulntype => vt.id, :verified => true, :falsepos => false, Vulnerability.test.application.record_type => @selectedRecordTypes, :created_at => (date...(date+7)))
					@datasets[key] << ct
					allcount += ct
				end

				otherCt = Vulnerability.countWithFlags(@selectedFlags, :vulntype => 0, :verified => true, :falsepos => false, Vulnerability.test.application.record_type => @selectedRecordTypes, :created_at => (date...(date+7)))
				
				@datasets["Custom/Other"] << otherCt
				allcount += otherCt

				@datasets["All"] << allcount
			end
		elsif(@int == "month")
			date = Date.new(@startdate.year, @startdate.month, 1)
			while date < @enddate do
				@labels << date.strftime('%B, %Y')
				allcount = 0

				@datasets.keys.each do |key|
					next if(key.downcase == "all" || key.downcase == "custom/other")
					vt = VulnType.getTypeByName(key)
					ct = Vulnerability.countWithFlags(@selectedFlags, :vulntype => vt.id, :verified => true, :falsepos => false, Vulnerability.test.application.record_type => @selectedRecordTypes, :created_at => (date..(date.end_of_month).to_datetime.end_of_day))
					@datasets[key] << ct
					allcount += ct
				end

				otherCt = Vulnerability.countWithFlags(@selectedFlags, :vulntype => 0, :verified => true, :falsepos => false, Vulnerability.test.application.record_type => @selectedRecordTypes, :created_at => (date..(date.end_of_month).to_datetime.end_of_day))
				
				@datasets["Custom/Other"] << otherCt
				allcount += otherCt

				@datasets["All"] << allcount

				date = (date >> 1)
			end
		elsif(@int == "quarter")
			first = (startOfQuarter(@startdate) < @startdate) ? @startdate : startOfQuarter(@startdate)
			last = (endOfQuarter(@startdate) > @enddate) ? @enddate : endOfQuarter(@startdate)
			while first < @enddate do
				@labels << "Q" + qnum(first).to_s + ", FY " + fy(first).to_s
				allcount = 0

				@datasets.keys.each do |key|
					next if(key.downcase == "all" || key.downcase == "custom/other")
					vt = VulnType.getTypeByName(key)
					ct = Vulnerability.countWithFlags(@selectedFlags, :vulntype => vt.id, :verified => true, :falsepos => false, Vulnerability.test.application.record_type => @selectedRecordTypes, :created_at => ((first.to_datetime)...(last.to_datetime.end_of_day)))
					@datasets[key] << ct
					allcount += ct
				end

				otherCt = Vulnerability.countWithFlags(@selectedFlags, :vulntype => 0, :verified => true, :falsepos => false, Vulnerability.test.application.record_type => @selectedRecordTypes, :created_at => ((first.to_datetime)...(last.to_datetime.end_of_day)))
				
				@datasets["Custom/Other"] << otherCt
				allcount += otherCt

				@datasets["All"] << allcount

				first = startOfQuarter(first >> 3)
				last = (endOfQuarter(first) > @enddate) ? @enddate : endOfQuarter(first)
			end
		elsif(@int == "year")
			first = @startdate.to_date
			last = Date.new(first.year, 12, 31)
			last = @enddate if @enddate < last
			while first < @enddate do
				@labels << first.strftime('%Y')
				allcount = 0
				
				@datasets.keys.each do |key|
					next if(key.downcase == "all" || key.downcase == "custom/other")
					vt = VulnType.getTypeByName(key)
					ct = Vulnerability.countWithFlags(@selectedFlags, :vulntype => vt.id, :verified => true, :falsepos => false, Vulnerability.test.application.record_type => @selectedRecordTypes, :created_at => ((first.to_datetime)...(last.to_datetime.end_of_day)))
					@datasets[key] << ct
					allcount += ct
				end

				otherCt = Vulnerability.countWithFlags(@selectedFlags, :vulntype => 0, :verified => true, :falsepos => false, Vulnerability.test.application.record_type => @selectedRecordTypes, :created_at => ((first.to_datetime)...(last.to_datetime.end_of_day)))

				@datasets["Custom/Other"] << otherCt
				allcount += otherCt

				@datasets["All"] << allcount

				first = Date.new((first.year+1), 1, 1)
				last = Date.new(first.year, 12, 31)
				last = @enddate.to_date if @enddate < last
			end
		end

		@totalVulns = @datasets["All"].inject(0, :+)

		erb :"reports/vulnsOverTime"
	end

	post '/reports/vulns/vulnerabilitiesOverTime/?' do
		datestring = (params[:alldata]) ? "all" : form_datestring(params[:startdate], params[:enddate])
		int = params[:interval]
		flags = form_flagstring(params[:appFlags], params[:flagSelectAll])
		rtStr = form_rtstring(params[:recordTypes], params[:rtSelectAll])

		redirect "/reports/vulns/vulnerabilitiesOverTime/#{datestring}/#{int}/#{flags}/#{rtStr}"
	end

	get '/reports/vulns/vulnerabilitiesOverTime/?' do
		redirect "/reports/vulns/vulnerabilitiesOverTime/default/month/all/all"
	end

	#####################
	# Stats by Reviewer #
	#####################

	get '/reports/reviewer/statsByReviewer/:rid/:period/:interval/:flags/:rt/?' do
		@formsub = "/reports/reviewer/statsByReviewer"
		@intervals = ["Day", "Week", "Month", "Quarter", "Year"]
		
		rid = params[:rid].to_i
		@reviewer = User.get(rid)
		if(@reviewer.nil?)
			@errstr = "User not found"
			return erb :error
		end
		
		@int, @intString = parseInterval(params[:interval].downcase, @intervals)
		@startdate, @enddate, @periodString = parsePeriod(params[:period].downcase)
		@selectedFlags, @appTypeString = parseFlags(params[:flags])
		@selectedRecordTypes = parseRt(params[:rt])

		@reviewers = Array.new
		addedToRev = Array.new
		User.all().each do |u|
			next if u.name.nil?
			next if(addedToRev.include?(u.name.downcase))
			@reviewers << {:id => u.id, :name => u.name}
			addedToRev << u.name.downcase
		end

		@labels = Array.new
		@testCounts = Array.new
		@testSum = Array.new
		@vulnCounts = Array.new
		@vulnSum = Array.new

		if(@int == "day")
			@startdate.upto(@enddate) do |date|
				@labels << date.strftime('%m-%d-%Y')
				vct = 0
				tct = 0
				Test.allWithFlags(@selectedFlags, :reviewer => rid, :complete => true, :closed_at => (date..date+1), Test.application.record_type => @selectedRecordTypes).each do |t|
					tct += 1
					vct += t.vulnerabilities.size
				end
				@testCounts << tct
				@testSum << @testCounts.inject(0, :+)
				@vulnCounts << vct
				@vulnSum << @vulnCounts.inject(0, :+)
			end
		elsif(@int == "week")
			@startdate.step(@enddate, 7) do |date|
				@labels << date.strftime('%m-%d-%Y')
				vct = 0
				tct = 0
				Test.allWithFlags(@selectedFlags, :reviewer => rid, :complete => true, :closed_at => (date..date+7), Test.application.record_type => @selectedRecordTypes).each do |t|
					tct += 1
					vct += t.vulnerabilities.size
				end
				@testCounts << tct
				@testSum << @testCounts.inject(0, :+)
				@vulnCounts << vct
				@vulnSum << @vulnCounts.inject(0, :+)
			end
		elsif(@int == "month")
			date = Date.new(@startdate.year, @startdate.month, 1)
			while date < @enddate do
				@labels << date.strftime('%B, %Y')
				vct = 0
				tct = 0
				Test.allWithFlags(@selectedFlags, :reviewer => rid, :complete => true, :closed_at => (date..(date.end_of_month).to_datetime.end_of_day), Test.application.record_type => @selectedRecordTypes).each do |t|
					tct += 1
					vct += t.vulnerabilities.size
				end
				@testCounts << tct
				@testSum << @testCounts.inject(0, :+)
				@vulnCounts << vct
				@vulnSum << @vulnCounts.inject(0, :+)
				date = (date >> 1)
			end
		elsif(@int == "quarter")
			first = (startOfQuarter(@startdate) < @startdate) ? @startdate : startOfQuarter(@startdate)
			last = (endOfQuarter(@startdate) > @enddate) ? @enddate : endOfQuarter(@startdate)
			while first < @enddate do
				@labels << "Q" + qnum(first).to_s + ", FY " + fy(first).to_s
				vct = 0
				tct = 0
				Test.allWithFlags(@selectedFlags, :reviewer => rid, :complete => true, :closed_at => ((first.to_datetime)...(last.to_datetime.end_of_day)), Test.application.record_type => @selectedRecordTypes).each do |t|
					tct += 1
					vct += t.vulnerabilities.size
				end
				@testCounts << tct
				@testSum << @testCounts.inject(0, :+)
				@vulnCounts << vct
				@vulnSum << @vulnCounts.inject(0, :+)
				first = startOfQuarter(first >> 3)
				last = (endOfQuarter(first) > @enddate) ? @enddate : endOfQuarter(first)
			end
		elsif(@int == "year")
			first = @startdate.to_date
			last = Date.new(first.year, 12, 31)
			last = @enddate if @enddate < last
			while first < @enddate do
				@labels << first.strftime('%Y')
				vct = 0
				tct = 0
				Test.allWithFlags(@selectedFlags, :reviewer => rid, :complete => true, :closed_at => ((first.to_datetime)...(last.to_datetime.end_of_day)), Test.application.record_type => @selectedRecordTypes).each do |t|
					tct += 1
					vct += t.vulnerabilities.size
				end
				@testCounts << tct
				@testSum << @testCounts.inject(0, :+)
				@vulnCounts << vct
				@vulnSum << @vulnCounts.inject(0, :+)
				first = Date.new((first.year+1), 1, 1)
				last = Date.new(first.year, 12, 31)
				last = @enddate.to_date if @enddate < last
			end
		end

		@totalTests = @testCounts.inject(0, :+)
		@totalVulns = @vulnCounts.inject(0, :+)
		@testsInProg = Test.count(:reviewer => rid, :complete => false)

		@activeReviews = Array.new
		@pastReviews = Array.new
		addedReviews = Array.new
		
		Test.allWithFlags(@selectedFlags, :complete => false, :reviewer => rid, :order => [ :id.asc ], :created_at => (@startdate..@enddate), Test.application.record_type => @selectedRecordTypes).each do |t|
			next if(addedReviews.include?(t.application_id))
			next if(!canViewReview?(t.application_id))

			@activeReviews << {:app => Application.get(t.application_id), :test => t}
			addedReviews << t.application_id
		end

		Test.allWithFlags(@selectedFlags, :complete => true, :reviewer => rid, :order => [ :id.desc ], :created_at => (@startdate..@enddate), Test.application.record_type => @selectedRecordTypes).each do |t|
			next if(addedReviews.include?(t.application_id))
			next if(!canViewReview?(t.application_id))

			@pastReviews << {:app => Application.get(t.application_id), :test => t}
			addedReviews << t.application_id
		end

		erb :"reports/statsByReviewer"
	end

	post '/reports/reviewer/statsByReviewer/?' do
		datestring = (params[:alldata]) ? "all" : form_datestring(params[:startdate], params[:enddate])
		int = params[:interval]
		rid = params[:rid].to_i	
		flags = form_flagstring(params[:appFlags], params[:flagSelectAll])
		rtStr = form_rtstring(params[:recordTypes], params[:rtSelectAll])

		redirect "/reports/reviewer/statsByReviewer/#{rid}/#{datestring}/#{int}/#{flags}/#{rtStr}"
	end

	get '/reports/reviewer/statsByReviewer/?' do
		redirect "/reports/reviewer/statsByReviewer/#{session[:uid]}/default/month/all/all"
	end

	#########################
	# Stats by Organization #
	#########################

	get '/reports/reviewer/statsByOrg/:oid/:period/:interval/:flags/:rt/?' do
		@formsub = "/reports/reviewer/statsByOrg"
		@intervals = ["Day", "Week", "Month", "Quarter", "Year"]
		
		oid = params[:oid].to_i
		@org = Organization.get(oid)
		if(@org.nil?)
			@errstr = "Organization not found"
			return erb :error
		end
		
		@int, @intString = parseInterval(params[:interval].downcase, @intervals)
		@startdate, @enddate, @periodString = parsePeriod(params[:period].downcase)
		@selectedFlags, @appTypeString = parseFlags(params[:flags])
		@selectedRecordTypes = parseRt(params[:rt])

		@orgs = Array.new
		addedToRev = Array.new
		Organization.all().each do |o|
			next if(addedToRev.include?(o.name.downcase))
			@orgs << {:id => o.id, :name => o.name}
			addedToRev << o.name.downcase
		end

		@labels = Array.new
		@testCounts = Array.new
		@testSum = Array.new
		@vulnCounts = Array.new
		@vulnSum = Array.new

		if(@int == "day")
			@startdate.upto(@enddate) do |date|
				@labels << date.strftime('%m-%d-%Y')
				vct = 0
				tct = 0
				Test.allWithFlags(@selectedFlags, :org_created => oid, :complete => true, :closed_at => (date..date+1), Test.application.record_type => @selectedRecordTypes).each do |t|
					tct += 1
					vct += Vulnerability.count(:test_id => t.id, :created_at => (date..date+1))
				end
				@testCounts << tct
				@testSum << @testCounts.inject(0, :+)
				@vulnCounts << vct
				@vulnSum << @vulnCounts.inject(0, :+)
			end
		elsif(@int == "week")
			@startdate.step(@enddate, 7) do |date|
				@labels << date.strftime('%m-%d-%Y')
				vct = 0
				tct = 0
				Test.allWithFlags(@selectedFlags, :org_created => oid, :complete => true, :closed_at => (date..date+7), Test.application.record_type => @selectedRecordTypes).each do |t|
					tct += 1
					vct += Vulnerability.count(:test_id => t.id, :created_at => (date..date+7))
				end
				@testCounts << tct
				@testSum << @testCounts.inject(0, :+)
				@vulnCounts << vct
				@vulnSum << @vulnCounts.inject(0, :+)
			end
		elsif(@int == "month")
			date = Date.new(@startdate.year, @startdate.month, 1)
			while date < @enddate do
				@labels << date.strftime('%B, %Y')
				vct = 0
				tct = 0
				Test.allWithFlags(@selectedFlags, :org_created => oid, :complete => true, :closed_at => (date..(date.end_of_month).to_datetime.end_of_day), Test.application.record_type => @selectedRecordTypes).each do |t|
					tct += 1
					vct += Vulnerability.count(:test_id => t.id, :created_at => (date..(date.end_of_month).to_datetime.end_of_day))
				end
				@testCounts << tct
				@testSum << @testCounts.inject(0, :+)
				@vulnCounts << vct
				@vulnSum << @vulnCounts.inject(0, :+)
				date = (date >> 1)
			end
		elsif(@int == "quarter")
			first = (startOfQuarter(@startdate) < @startdate) ? @startdate : startOfQuarter(@startdate)
			last = (endOfQuarter(@startdate) > @enddate) ? @enddate : endOfQuarter(@startdate)
			while first < @enddate do
				@labels << "Q" + qnum(first).to_s + ", FY " + fy(first).to_s
				vct = 0
				tct = 0
				Test.allWithFlags(@selectedFlags, :org_created => oid, :complete => true, :closed_at => ((first.to_datetime)...(last.to_datetime.end_of_day)), Test.application.record_type => @selectedRecordTypes).each do |t|
					tct += 1
					vct += Vulnerability.count(:test_id => t.id, :created_at => ((first.to_datetime)...(last.to_datetime.end_of_day)))
				end
				@testCounts << tct
				@testSum << @testCounts.inject(0, :+)
				@vulnCounts << vct
				@vulnSum << @vulnCounts.inject(0, :+)
				first = startOfQuarter(first >> 3)
				last = (endOfQuarter(first) > @enddate) ? @enddate : endOfQuarter(first)
			end
		elsif(@int == "year")
			first = @startdate.to_date
			last = Date.new(first.year, 12, 31)
			last = @enddate if @enddate < last
			while first < @enddate do
				@labels << first.strftime('%Y')
				vct = 0
				tct = 0
				Test.allWithFlags(@selectedFlags, :org_created => oid, :complete => true, :closed_at => ((first.to_datetime)...(last.to_datetime.end_of_day)), Test.application.record_type => @selectedRecordTypes).each do |t|
					tct += 1
					vct += Vulnerability.count(:test_id => t.id, :created_at => ((first.to_datetime)...(last.to_datetime.end_of_day)))
				end
				@testCounts << tct
				@testSum << @testCounts.inject(0, :+)
				@vulnCounts << vct
				@vulnSum << @vulnCounts.inject(0, :+)
				first = Date.new((first.year+1), 1, 1)
				last = Date.new(first.year, 12, 31)
				last = @enddate.to_date if @enddate < last
			end
		end

		@totalTests = @testCounts.inject(0, :+)
		@totalVulns = @vulnCounts.inject(0, :+)
		@testsInProg = Test.countWithFlags(@selectedFlags, :org_created => oid, :complete => false, Test.application.record_type => @selectedRecordTypes)

		erb :"reports/statsByOrg"
	end

	post '/reports/reviewer/statsByOrg/?' do
		datestring = (params[:alldata]) ? "all" : form_datestring(params[:startdate], params[:enddate])
		int = params[:interval]
		oid = params[:oid].to_i	
		flags = form_flagstring(params[:appFlags], params[:flagSelectAll])
		rtStr = form_rtstring(params[:recordTypes], params[:rtSelectAll])

		redirect "/reports/reviewer/statsByOrg/#{oid}/#{datestring}/#{int}/#{flags}/#{rtStr}"
	end

	get '/reports/reviewer/statsByOrg/?' do
		redirect "/reports/reviewer/statsByOrg/#{session[:org]}/default/month/all/all"
	end

	###########################
	#Tests and Apps over Time #
	###########################

	get '/reports/tests/testsOverTime/:period/:interval/:flags/:rt/?' do
		@formsub = "/reports/tests/testsOverTime"
		@intervals = ["Day", "Week", "Month", "Quarter", "Year"]
		
		@int, @intString = parseInterval(params[:interval].downcase, @intervals)
		@startdate, @enddate, @periodString = parsePeriod(params[:period].downcase)
		@selectedFlags, @appTypeString = parseFlags(params[:flags])
		@selectedRecordTypes = parseRt(params[:rt])

		@labels = Array.new
		@appCounts = Array.new
		@testCounts = Array.new
		@nonConTestCounts = Array.new
		@conTestCounts = Array.new

		appsIncludedTotal = Array.new
		@appCountTotal = 0

		if(@int == "day")
			@startdate.upto(@enddate) do |date|
				@labels << date.strftime('%a %m-%d-%Y')
				act = 0
				stct = 0
				ctct = 0
				
				appsIncluded = Array.new
				Test.allWithFlags(@selectedFlags, :complete => true, :closed_at => (date.to_datetime.beginning_of_day..(date.to_datetime.end_of_day)), Test.application.record_type => @selectedRecordTypes).each do |t|
					if(t.contractor_test)
						ctct += 1
					else
						stct += 1
					end

					if(!appsIncluded.include?(t.application_id))
						act += 1
						appsIncluded << t.application_id
					end

					if(!appsIncludedTotal.include?(t.application_id))
						@appCountTotal += 1
						appsIncludedTotal << t.application_id
					end
				end

				@testCounts << (stct + ctct)
				@nonConTestCounts << stct
				@conTestCounts << ctct
				@appCounts << act
			end
		elsif(@int == "week")
			@startdate.step(@enddate, 7) do |date|
				@labels << date.strftime('%m-%d-%Y')
				act = 0
				stct = 0
				ctct = 0
				
				appsIncluded = Array.new
				Test.allWithFlags(@selectedFlags, :complete => true, :closed_at => (date.to_datetime.beginning_of_day..(date+7).to_datetime.end_of_day), Test.application.record_type => @selectedRecordTypes).each do |t|
					if(t.contractor_test)
						ctct += 1
					else
						stct += 1
					end

					if(!appsIncluded.include?(t.application_id))
						act += 1
						appsIncluded << t.application_id
					end

					if(!appsIncludedTotal.include?(t.application_id))
						@appCountTotal += 1
						appsIncludedTotal << t.application_id
					end
				end

				@testCounts << (stct + ctct)
				@nonConTestCounts << stct
				@conTestCounts << ctct
				@appCounts << act
			end
		elsif(@int == "month")
			date = Date.new(@startdate.year, @startdate.month, 1)
			while date < @enddate do
				@labels << date.strftime('%B, %Y')
				act = 0
				stct = 0
				ctct = 0
				
				appsIncluded = Array.new
				Test.allWithFlags(@selectedFlags, :complete => true, :closed_at => (date.to_datetime.beginning_of_day..(date.end_of_month.to_datetime.end_of_day)), Test.application.record_type => @selectedRecordTypes).each do |t|
					if(t.contractor_test)
						ctct += 1
					else
						stct += 1
					end

					if(!appsIncluded.include?(t.application_id))
						act += 1
						appsIncluded << t.application_id
					end

					if(!appsIncludedTotal.include?(t.application_id))
						@appCountTotal += 1
						appsIncludedTotal << t.application_id
					end
				end

				@testCounts << (stct + ctct)
				@nonConTestCounts << stct
				@conTestCounts << ctct
				@appCounts << act

				date = (date >> 1)
			end
		elsif(@int == "quarter")
			first = (startOfQuarter(@startdate) < @startdate) ? @startdate : startOfQuarter(@startdate)
			last = (endOfQuarter(@startdate) > @enddate) ? @enddate : endOfQuarter(@startdate)
			while first < @enddate do
				@labels << "Q" + qnum(first).to_s + ", FY " + fy(first).to_s
				act = 0
				stct = 0
				ctct = 0
				
				appsIncluded = Array.new
				Test.allWithFlags(@selectedFlags, :complete => true, :closed_at => ((first.to_datetime.beginning_of_day)...(last.to_datetime.end_of_day)), Test.application.record_type => @selectedRecordTypes).each do |t|
					if(t.contractor_test)
						ctct += 1
					else
						stct += 1
					end

					if(!appsIncluded.include?(t.application_id))
						act += 1
						appsIncluded << t.application_id
					end

					if(!appsIncludedTotal.include?(t.application_id))
						@appCountTotal += 1
						appsIncludedTotal << t.application_id
					end
				end

				@testCounts << (stct + ctct)
				@nonConTestCounts << stct
				@conTestCounts << ctct
				@appCounts << act

				first = startOfQuarter(first >> 3)
				last = (endOfQuarter(first) > @enddate) ? @enddate : endOfQuarter(first)
			end
		elsif(@int == "year")
			first = @startdate.to_date
			last = Date.new(first.year, 12, 31)
			last = @enddate if @enddate < last
			while first < @enddate do
				@labels << first.strftime('%Y')
				act = 0
				stct = 0
				ctct = 0
				
				appsIncluded = Array.new
				Test.allWithFlags(@selectedFlags, :complete => true, :closed_at => ((first.to_datetime.beginning_of_day)...(last.to_datetime.end_of_day)), Test.application.record_type => @selectedRecordTypes).each do |t|
					if(t.contractor_test)
						ctct += 1
					else
						stct += 1
					end

					if(!appsIncluded.include?(t.application_id))
						act += 1
						appsIncluded << t.application_id
					end

					if(!appsIncludedTotal.include?(t.application_id))
						@appCountTotal += 1
						appsIncludedTotal << t.application_id
					end
				end

				@testCounts << (stct + ctct)
				@nonConTestCounts << stct
				@conTestCounts << ctct
				@appCounts << act

				first = Date.new((first.year+1), 1, 1)
				last = Date.new(first.year, 12, 31)
				last = @enddate.to_date if @enddate < last
			end
		end

		@totalTests = @testCounts.inject(0, :+)
		@totalNonConTests = @nonConTestCounts.inject(0, :+)
		@totalConTests = @conTestCounts.inject(0, :+)
		@totalApps = @appCounts.inject(0, :+)

		erb :"reports/testsOverTime"
	end

	post '/reports/tests/testsOverTime/?' do
		datestring = (params[:alldata]) ? "all" : form_datestring(params[:startdate], params[:enddate])
		int = params[:interval]		
		flags = form_flagstring(params[:appFlags], params[:flagSelectAll])
		rtStr = form_rtstring(params[:recordTypes], params[:rtSelectAll])

		redirect "/reports/tests/testsOverTime/#{datestring}/#{int}/#{flags}/#{rtStr}"
	end

	get '/reports/tests/testsOverTime/?' do
		redirect "/reports/tests/testsOverTime/default/month/all/all"
	end

	########################
	#Resolutions over Time #
	########################

	get '/reports/tests/resolutionsOverTime/:period/:interval/:flags/:rt/?' do
		@formsub = "/reports/tests/resolutionsOverTime"
		@intervals = ["Day", "Week", "Month", "Quarter", "Year"]
		
		@int, @intString = parseInterval(params[:interval].downcase, @intervals)
		@startdate, @enddate, @periodString = parsePeriod(params[:period].downcase)
		@selectedFlags, @appTypeString = parseFlags(params[:flags])
		@selectedRecordTypes = parseRt(params[:rt])

		@labels = Array.new
		@appCounts = Array.new
		@testCounts = Array.new
		@passCounts = Array.new
		@failCounts = Array.new

		if(@int == "day")
			@startdate.upto(@enddate) do |date|
				@labels << date.strftime('%a %m-%d-%Y')
				act = 0
				passct = 0
				failct = 0
				
				appsIncluded = Array.new
				Test.allWithFlags(@selectedFlags, :complete => true, :closed_at => (date.to_datetime.beginning_of_day..(date.to_datetime.end_of_day)), Test.application.record_type => @selectedRecordTypes).each do |t|
					if(t.complete && t.pass)
						passct += 1
					else
						failct += 1
					end

					if(!appsIncluded.include?(t.application_id))
						act += 1
						appsIncluded << t.application_id
					end
				end

				@testCounts << (passct + failct)
				@passCounts << passct
				@failCounts << failct
				@appCounts << act
			end
		elsif(@int == "week")
			@startdate.step(@enddate, 7) do |date|
				@labels << date.strftime('%m-%d-%Y')
				act = 0
				passct = 0
				failct = 0
				
				appsIncluded = Array.new
				Test.allWithFlags(@selectedFlags, :complete => true, :closed_at => (date..(date+7)).to_datetime.end_of_day, Test.application.record_type => @selectedRecordTypes).each do |t|
					if(t.complete && t.pass)
						passct += 1
					else
						failct += 1
					end

					if(!appsIncluded.include?(t.application_id))
						act += 1
						appsIncluded << t.application_id
					end
				end

				@testCounts << (passct + failct)
				@passCounts << passct
				@failCounts << failct
				@appCounts << act
			end
		elsif(@int == "month")
			date = Date.new(@startdate.year, @startdate.month, 1)
			while date < @enddate do
				@labels << date.strftime('%B, %Y')
				act = 0
				passct = 0
				failct = 0
				
				appsIncluded = Array.new
				Test.allWithFlags(@selectedFlags, :complete => true, :closed_at => (date..(date.end_of_month).to_datetime.end_of_day), Test.application.record_type => @selectedRecordTypes).each do |t|
					if(t.complete && t.pass)
						passct += 1
					else
						failct += 1
					end

					if(!appsIncluded.include?(t.application_id))
						act += 1
						appsIncluded << t.application_id
					end
				end

				@testCounts << (passct + failct)
				@passCounts << passct
				@failCounts << failct
				@appCounts << act

				date = (date >> 1)
			end
		elsif(@int == "quarter")
			first = (startOfQuarter(@startdate) < @startdate) ? @startdate : startOfQuarter(@startdate)
			last = (endOfQuarter(@startdate) > @enddate) ? @enddate : endOfQuarter(@startdate)
			while first < @enddate do
				@labels << "Q" + qnum(first).to_s + ", FY " + fy(first).to_s
				act = 0
				passct = 0
				failct = 0
				
				appsIncluded = Array.new
				Test.allWithFlags(@selectedFlags, :complete => true, :closed_at => (date..(date.end_of_month).to_datetime.end_of_day), Test.application.record_type => @selectedRecordTypes).each do |t|
					if(t.complete && t.pass)
						passct += 1
					else
						failct += 1
					end

					if(!appsIncluded.include?(t.application_id))
						act += 1
						appsIncluded << t.application_id
					end
				end

				@testCounts << (passct + failct)
				@passCounts << passct
				@failCounts << failct
				@appCounts << act

				first = startOfQuarter(first >> 3)
				last = (endOfQuarter(first) > @enddate) ? @enddate : endOfQuarter(first)
			end
		elsif(@int == "year")
			first = @startdate.to_date
			last = Date.new(first.year, 12, 31)
			last = @enddate if @enddate < last
			while first < @enddate do
				@labels << first.strftime('%Y')
				act = 0
				passct = 0
				failct = 0
				
				appsIncluded = Array.new
				Test.allWithFlags(@selectedFlags, :complete => true, :closed_at => ((first.to_datetime)...(last.to_datetime.end_of_day)), Test.application.record_type => @selectedRecordTypes).each do |t|
					if(t.complete && t.pass)
						passct += 1
					else
						failct += 1
					end

					if(!appsIncluded.include?(t.application_id))
						act += 1
						appsIncluded << t.application_id
					end
				end

				@testCounts << (passct + failct)
				@passCounts << passct
				@failCounts << failct
				@appCounts << act

				first = Date.new((first.year+1), 1, 1)
				last = Date.new(first.year, 12, 31)
				last = @enddate.to_date if @enddate < last
			end
		end

		@totalTests = @testCounts.inject(0, :+)
		@totalPasses = @passCounts.inject(0, :+)
		@totalFails = @failCounts.inject(0, :+)
		@totalApps = @appCounts.inject(0, :+)

		erb :"reports/resolutionsOverTime"
	end

	post '/reports/tests/resolutionsOverTime/?' do
		datestring = (params[:alldata]) ? "all" : form_datestring(params[:startdate], params[:enddate])
		int = params[:interval]		
		flags = form_flagstring(params[:appFlags], params[:flagSelectAll])
		rtStr = form_rtstring(params[:recordTypes], params[:rtSelectAll])

		redirect "/reports/tests/resolutionsOverTime/#{datestring}/#{int}/#{flags}/#{rtStr}"
	end

	get '/reports/tests/resolutionsOverTime/?' do
		redirect "/reports/tests/resolutionsOverTime/default/month/all/all"
	end

	#############################
	# Search Tests by Vuln Type #
	#############################

	get '/reports/tests/searchByVuln/?' do
		@formsub = "/reports/tests/searchByVuln"

		@vts = VulnType.all().sort{ |x,y| x.name <=> y.name}
		@selectedFlags, @appTypeString = parseFlags('all')

		erb :"reports/testsByVuln"
	end

	post '/reports/tests/searchByVuln/?' do
		@formsub = "/reports/tests/searchByVuln"

		@vts = VulnType.all().sort{ |x,y| x.name <=> y.name}

		@period = (params[:alldata]) ? "all" : form_datestring(params[:startdate], params[:enddate])		
		
		@startdate, @enddate, @periodString = parsePeriod(@period)
		@selectedFlags, @appTypeString = parseFlags(form_flagstring(params[:appFlags], params[:flagSelectAll]))
		@allowedRecordTypes = getAllowedRTsForUser(@session[:uid])
		@selectedRecordTypes = params[:recordTypes]
		rtSelectAll = (!params[:rtSelectAll].nil? && params[:rtSelectAll].to_s.downcase == "all")
		if(rtSelectAll || @selectedRecordTypes.nil? || @selectedRecordTypes.empty?)
			@selectedRecordTypes = @allowedRecordTypes
		else
			@selectedRecordTypes = @allowedRecordTypes & @selectedRecordTypes.map{|n| n.to_i}
		end

		@cond = params[:cond].downcase
		if(@cond != "any" && @cond != "all")
			@cond = "any"
		end

		if(params[:vts].nil?)
			@errstr = "At least one vulnerability type must be selected"
			return erb :error
		end
		
		@selVTs = params[:vts].map { |e| e.to_i }
		@matches = Array.new
		(Test.allWithFlags(@selectedFlags, :created_at => (@startdate..@enddate), Test.application.record_type => @selectedRecordTypes) | Test.allWithFlags(@selectedFlags, :closed_at => (@startdate..@enddate), Test.application.record_type => @selectedRecordTypes)).each do |t|
			vulns = t.vulnerabilities
			if(@cond == "any")
				vulns.each do |v|
					if(@selVTs.include?(v.vulntype))
						@matches << t unless @matches.include?(t)
						break
					end
				end
			else
				testVTIDs = Array.new
				vulns.each do |v|
					testVTIDs << v.vulntype unless testVTIDs.include?(v.vulntype)
				end
				match = true
				@selVTs.each do |vtid|
					if(!testVTIDs.include?(vtid))
						match = false
						break
					end
				end
				@matches << t if (match && !@matches.include?(t))
			end
		end

		erb :"reports/testsByVuln"
	end

	########################
	# Allocation - Current #
	########################

	get '/reports/alloc/:month/:year/?' do
		@users = User.all(:useAllocation => true, :active => true)
		@totalReviewsAllocated = 0
		@totalReviewsActual = 0
		@totalTestsActual = 0

		@data = Hash.new

		yr = params[:year].to_i
		month = params[:month].to_i

		if(yr < 2014 || yr > 2020 || month < 1 || month > 12)
			@startDate = Date.today.at_beginning_of_month
		else
			@startDate = Date.new(yr, month, 1)
		end
		endDate = @startDate >> 1

		MonthlyAllocation.all(:month => month, :year => yr).each do |ma|
			found = false
			@users.each do |u|
				found = true if(u.id == ma.uid)
			end

			@users << User.get(ma.uid) if !found
		end

		@users.each do |u|
			a = MonthlyAllocation.allocationForUser(u.id, month=@startDate.month, year=@startDate.year)
			if a.nil?
				allocCoeff = 0
				a = 0
				allocNil = true
				autoSet = false
			else
				autoSet = a.wasAutoSet
				allocCoeff = a.coeff
				a = a.allocation
				allocNil = false
			end
			allocPct = a
			allocApps = (((u.allocCoeff.to_f)/12.0)*(a.to_f/100.0))
			@totalReviewsAllocated += allocApps.round

			testsThisReviewer = 0
			appsThisReviewer = Array.new
			Test.all(:reviewer => u.id, :complete => true, :closed_at => (@startDate..endDate)).each do |t|
				testsThisReviewer += 1
				if(!appsThisReviewer.include?(t.application_id))
					appsThisReviewer << t.application_id
				end
			end


			@data[u.id] = {:allocNil => allocNil, :auto => autoSet, :allocPct => allocPct, :allocCoeff => allocCoeff, :allocApps => allocApps, :apps => appsThisReviewer, :numTests => testsThisReviewer}
			@totalReviewsActual += appsThisReviewer.length
			@totalTestsActual += testsThisReviewer
		end

		@totalReviewsAllocated = @totalReviewsAllocated

		erb :"reports/allocThisMonth"
	end

	get '/reports/alloc/thisMonth/?' do
		d = Date.today.at_beginning_of_month
		redirect "/reports/alloc/#{d.month}/#{d.year}"
	end

	#########################
	# Allocation Date Range #
	#########################

	get '/reports/alloc/forRange/:period/:interval/:rt/?' do
		@formsub = "/reports/alloc/forRange"
		@intervals = ["Total"]

		@int, @intString = parseInterval(params[:interval].downcase, @intervals, "total")
		@startdate, @enddate, @periodString = parsePeriod(params[:period].downcase, nil, Date.today.prev_month.end_of_month.to_datetime.end_of_day)
		@selectedFlags, @appTypeString = parseFlags(params[:flags])
		@selectedRecordTypes = parseRt(params[:rt])

		@data = Hash.new

		curDate = Date.new(@startdate.year, @startdate.month, @startdate.day)
		while(curDate < @enddate)
			MonthlyAllocation.all(:month => curDate.month, :year => curDate.year).each do |ma|
				u = User.get(ma.uid)
				next if(u.nil?)

				allocApps = (((ma.coeff.to_f)/12.0)*((ma.allocation.to_f)/100.0)).round

				if(@data[ma.uid].nil?)					
					@data[ma.uid] = {:name => u.name, :allocApps => allocApps, :uniqueApps => 0, :numTests => 0}
				else
					@data[ma.uid][:allocApps] += allocApps
				end
			end

			curDate = curDate >> 1
		end

		@data.keys.each do |uid|
			testsThisReviewer = 0
			appsThisReviewer = Array.new
			Test.all(:reviewer => uid, :complete => true, :closed_at => (@startdate..@enddate), Test.application.record_type => @selectedRecordTypes).each do |t|
				testsThisReviewer += 1
				if(!appsThisReviewer.include?(t.application_id))
					appsThisReviewer << t.application_id
				end
			end

			@data[uid][:uniqueApps] += appsThisReviewer.size
			@data[uid][:numTests] += testsThisReviewer

			if(@data[uid][:allocApps] == 0 && @data[uid][:uniqueApps] == 0 && @data[uid][:numTests] == 0)
				@data.delete(uid)
			end
		end

		erb :"reports/allocForRange"
	end

	post '/reports/alloc/forRange/?' do
		datestring = (params[:alldata]) ? "all" : form_datestring(params[:startdate], params[:enddate])
		int = params[:interval]
		rtStr = form_rtstring(params[:recordTypes], params[:rtSelectAll])
		redirect "/reports/alloc/forRange/#{datestring}/#{int}/#{rtStr}"
	end

	get '/reports/alloc/forRange/?' do
		startdate = Date.today.beginning_of_month.strftime('%m-%d-%Y')
		enddate = Date.today.end_of_month.strftime('%m-%d-%Y')
		redirect "/reports/alloc/forRange/#{startdate}...#{enddate}/total/all"
	end

	##########################
	# Historical Allocation  #
	##########################

	##########################
	# Historical Allocation  #
	##########################

	get '/reports/alloc/userHistorical/:period/:interval/?' do
		@formsub = "/reports/alloc/userHistorical"
		@intervals = ["Month", "Quarter"]
		
		@int, @intString = parseInterval(params[:interval].downcase, @intervals)
		@startdate, @enddate, @periodString = parsePeriod(params[:period].downcase)
		
		@datasets_rev = Hash.new
		@datasets_rev["All"] = Array.new

		User.all(:useAllocation => true).each do |u|
			@datasets_rev[u.name] = Array.new
		end

		@labels = Array.new
		
		if(@int == "month")
			date = Date.new(@startdate.year, @startdate.month, 1)
			while date < @enddate do
				@labels << date.strftime('%B, %Y')
				allcount = 0
				
				User.all(:useAllocation => true).each do |u|
					alloc = MonthlyAllocation.allocationForUser(u.id, date.month, date.year)
					if(alloc.nil?)
						coeff = 0
						alloc = 0
					else
						coeff = alloc.coeff
						alloc = alloc.allocation
					end

					@datasets_rev[u.name] << (((coeff.to_f)/12.0)*(alloc.to_f/100.0)).round
					allcount += (((coeff.to_f)/12.0)*(alloc.to_f/100.0))
				end

				@datasets_rev["All"] << allcount.round

				date = (date >> 1)
			end
		elsif(@int == "quarter")
			first = (startOfQuarter(@startdate) < @startdate) ? @startdate : startOfQuarter(@startdate)
			last = (endOfQuarter(@startdate) > @enddate) ? @enddate : endOfQuarter(@startdate)
			while first < @enddate do
				@labels << "Q" + qnum(first).to_s + ", FY " + fy(first).to_s
				allcount = 0
				
				User.all(:useAllocation => true).each do |u|
					alloc = 0
					curDate = first
					while(curDate.month <= last.month)
						thisAlloc = MonthlyAllocation.allocationForUser(u.id, curDate.month, curDate.year)
						if(thisAlloc.nil?)
							alloc += 0 
						else
							alloc += (((thisAlloc.coeff.to_f)/12.0)*(thisAlloc.allocation.to_f/100.0)).round
						end

						curDate = curDate >> 1
					end

					@datasets_rev[u.name] << alloc
					allcount += alloc
				end

				@datasets_rev["All"] << allcount
				
				first = startOfQuarter(first >> 3)
				last = (endOfQuarter(first) > @enddate) ? @enddate : endOfQuarter(first)
			end
		end

		erb :"reports/histAllocation"
	end

	post '/reports/alloc/userHistorical/?' do
		datestring = (params[:alldata]) ? "all" : form_datestring(params[:startdate], params[:enddate])
		int = params[:interval]		
		redirect "/reports/alloc/userHistorical/#{datestring}/#{int}"
	end

	get '/reports/alloc/userHistorical/?' do
		redirect "/reports/alloc/userHistorical/default/month"
	end

	#####################################
	# Allocation v Apps (Total or User) #
	#####################################

	get '/reports/alloc/allocVTests/:rid/:period/:interval/?' do
		@formsub = "/reports/alloc/allocVTests"
		@intervals = ["Month"]
		
		if(params[:rid] == "total" || params[:rid] == "0")
			rid = 0
			@reviewer = User.new(:id => 0, :name => "Total")
		else
			rid = params[:rid].to_i
			@reviewer = User.get(rid)
			if(@reviewer.nil?)
				@errstr = "User not found"
				return erb :error
			end
		end
		
		@int, @intString = parseInterval(params[:interval].downcase, @intervals)
		@startdate, @enddate, @periodString = parsePeriod(params[:period].downcase)

		@reviewers = Array.new
		addedToRev = Array.new
		User.all().each do |u|
			next if u.name.nil?
			next if(addedToRev.include?(u.name.downcase))
			@reviewers << {:id => u.id, :name => u.name}
			addedToRev << u.name.downcase
		end

		@labels = Array.new
		@data_alloc = Array.new
		@data_actual = Array.new
		
		if(@int == "month")
			date = Date.new(@startdate.year, @startdate.month, 1)
			while date < @enddate do
				@labels << date.strftime('%B, %Y')
				
				if(rid == 0)
					@users = User.all(:useAllocation => true)
					MonthlyAllocation.all(:month => date.month, :year => date.year).each do |ma|
						found = false
						@users.each do |u|
							found = true if(u.id == ma.uid)
						end

						@users << User.get(ma.uid) if !found
					end

					totalReviewsAllocated = 0
					totalReviewsActual = 0

					@users.each do |u|
						a = MonthlyAllocation.allocationForUser(u.id, date.month, date.year)
						if a.nil?
							coeff = 0
							a = 0
						else
							coeff = a.coeff
							a = a.allocation
						end
						totalReviewsAllocated += (((coeff.to_f)/12.0)*(a.to_f/100.0)).round

						testsThisReviewer = 0
						appsThisReviewer = Array.new
						Test.all(:reviewer => u.id, :complete => true, :closed_at => (date..(date.end_of_month).to_datetime.end_of_day)).each do |t|
							testsThisReviewer += 1
							if(!appsThisReviewer.include?(t.application_id))
								appsThisReviewer << t.application_id
							end
						end
						totalReviewsActual += appsThisReviewer.length
					end
					@data_alloc << totalReviewsAllocated
					@data_actual << totalReviewsActual
				else
					alloc = MonthlyAllocation.allocationForUser(rid, date.month, date.year)
					if alloc.nil?
						coeff = 0
						alloc = 0
					else
						coeff = alloc.coeff
						alloc = alloc.allocation
					end

					allocPct = alloc
					allocApps = (((coeff.to_f)/12.0)*(alloc.to_f/100.0)).round

					thisTests = 0
					thisApps = Array.new
					Test.all(:reviewer => rid, :complete => true, :closed_at => (date..(date.end_of_month).to_datetime.end_of_day)).each do |t|
						thisTests += 1
						if(!thisApps.include?(t.application_id))
							thisApps << t.application_id
						end
					end

					@data_alloc << allocApps
					@data_actual << thisApps.length
				end

				date = (date >> 1)
			end
		end

		@rangeTotalAllocated = @data_alloc.inject(0, :+)
		@rangeTotalActual = @data_actual.inject(0, :+)

		erb :"reports/allocVTests"
	end

	post '/reports/alloc/allocVTests/?' do
		datestring = (params[:alldata]) ? "all" : form_datestring(params[:startdate], params[:enddate])
		int = params[:interval]		
		rid = params[:rid].to_i
		redirect "/reports/alloc/allocVTests/#{rid}/#{datestring}/#{int}"
	end

	get '/reports/alloc/allocVTests/?' do
		redirect "/reports/alloc/allocVTests/total/default/month"
	end

	############
	# Sys Dash #
	############

	get '/reports/sys/dash/?' do
		@numApps = Application.count()
		@numTests = Test.count()
		@numVulns = Vulnerability.count()
		@numFlags = ApplicationFlag.count()
		@numUsers = User.count()
		@numOrgs = Organization.count()
		@numComments = Comment.count()
		@numNotifications = Notification.count()
		@auditCount = AuditRecord.count()

		erb :"reports/sysdash"
	end

	#########
	# Index #
	#########

	get '/reports/?' do
		if(reports_only?)
			erb :reports_index_reporters
		else
			erb :reports_index
		end
	end
end