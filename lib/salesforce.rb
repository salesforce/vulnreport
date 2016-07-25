##
# Copyright (c) 2016, salesforce.com, inc.
# All rights reserved.
# Licensed under the BSD 3-Clause license. 
# For full license text, see LICENSE.txt file in the repo root  or https://opensource.org/licenses/BSD-3-Clause
##

require 'savon'
require 'rforce'
require 'xmlsimple'
require 'base64'
require 'redis'
require 'json'

require_relative 'funcs'

##
# Handles all interactions with Salesforce instances
# @note About dealing with faults: a :fault Hash has keys :faultcode and :faultstring. Faultcode is guaranteed to exist 
#  and is what should be used programatically to deal with errors. :faultstring *should* exist and if it differs from
#  :faultcode it will be the more UI-paletable string.
#
# This class can be useful for writing {VRLinkedObject}s that interact with a Salesforce instance to manage your review process.
# See the example Salesforce Class SObject {VRLinkedObject} for an idea. At Salesforce we use an expaneded version of
# this library to interact with custom objects in 4 different Salesforce orgs programatically, using Vulnreport to manage
# the entire review process without our engineers having to look in 4 orgs/perform actions on all the different objects.
#
class Salesforce
	@@redis = Redis.new(:url => ENV['REDIS_URL'])

	##
	# Increments the number of times the Redis cache has been hit, saving an external interaction
	# Stores in Redis, offloads to DB backing every 25 hits
	# @return [Void]
	def self.countCacheHit()
		if(@@redis.get("cache_hits").nil?)
			@@redis.set("cache_hits", "1")
		else
			cur = @@redis.get("cache_hits").to_i
			cur += 1
			if(cur >= 25)
				stored = getSetting("cache_hits")
				if(stored.nil?)
					toStore = cur
				else
					toStore = stored.to_i + cur.to_i
				end
				setSetting("cache_hits", toStore.to_s)
				cur = 0
			end
			@@redis.set("cache_hits", cur.to_s)
		end
	end

	##
	# Increments the number of times the Redis cache has been hit, saving an external interaction
	# Stores in Redis, offloads to DB backing every 25 hits
	# @return [Void]
	def self.countCacheMiss()
		if(@@redis.get("cache_misses").nil?)
			@@redis.set("cache_misses", "1")
		else
			cur = @@redis.get("cache_misses").to_i
			cur += 1
			if(cur >= 25)
				stored = getSetting("cache_misses")
				if(stored.nil?)
					toStore = cur
				else
					toStore = stored.to_i + cur
				end
				setSetting("cache_misses", toStore.to_s)
				cur = 0
			end
			@@redis.set("cache_misses", cur.to_s)
		end
	end

	##
	# Attempt to login to a Salesforce org. If successful and a store parameter is given, store the SID in Redis with that key.
	# Login attempt uses the partner WSDL against the login.salesforce.com SOAP endpoint, version 29.0
	# @param username [String] the Username to attempt login with
	# @param password [String] the Password to attempt login with
	# @param store [String] the Redis key suffix to store the SID under if login is successful. If nil, the SID will not be stored, only returned.
	# @return [Hash] of success [Boolean], sid [String], surl [String] of the server URL for the authenticated ord, and userFullName [String] of the authenticated User's name if successful.
	# @return [Hash] of success [Boolean] and faultcode [String] of the error if login attempt is unsuccessful.
	def self.Login(username, password, store=nil)
		HTTPI.log = false
		client = Savon.client(wsdl: "wsdl/partner.wsdl", endpoint: "https://login.salesforce.com/services/Soap/u/29.0", :log_level => :fatal, :log => false)
		
		begin
			response = client.call(:login, :message => {:username => username, :password => password})
			result = response.to_hash[:login_response][:result]

			sid = result[:session_id]
			surl = result[:server_url]
			userFullName = result[:user_info][:user_full_name]

			if(!store.nil?)
				@@redis.setex("session_#{store}", 60*20, sid)
			end

			return {:success => true, :sid => sid, :surl => surl, :userFullName => userFullName}
		rescue Savon::SOAPFault => fault
			Rollbar.error(fault, "Vulnreport / Salesforce Login Error", {:org => store, :faultcode => fault.to_hash[:fault][:faultcode]})
			logputs "** LOGIN ERROR TO #{store} **"
			logputs fault.to_hash.to_s
			return {:success => false, :sid => nil, :surl => nil, :userFullName => nil, :faultcode => fault.to_hash[:fault][:faultcode]}
		end
	end

	##
	# Given a server URL and a Redis key for a stored SFDC SID, verify if the SID is active/valid
	# @param surl [String] Server URL
	# @param store [String] Redis key suffix where the SID is stored
	# @return [Boolean] true if the session is valid, false otherwise
	def self.verifySID?(surl, store)
		binding = RForce::Binding.new surl, @@redis.get("session_#{store}")
		loginResult = nil
		begin
			loginResult = binding.getUserInfo
		rescue
			return false
		end

		if(loginResult.nil? || !loginResult[:Fault].nil?)
			return false
		end

		return true
	end

	##
	# Perform a specified SOQL query against a specified Salesforce org and return the results (if successful) or error/fault
	# codes if the query was unsuccessful. If the query failed, log the exception and stack to Rollbar for later diagnostics.
	# Note that this funciton handles only "simple" SOQL queries. Long queries requiring the use of the queryLocator and queryMore
	# will be handled on a one-off basis in their individual methods to more properly handle the use cases.
	# @param org [String] Org to query against
	# @param soql [String] Raw SOQL query
	# @param isRetry [Boolean] if this method is being called a second time to retry due to invalid session, etc.
	# @return [Hash] Hash of :success [Boolean] overall success of the query, :records [Array] Records returned by query if
	#  query was successful (nil if unsuccessful), :size [Integer] the number of records returned if query was successful,
	#  :fault [Hash] Fault details (faultcode, faultstring) if query failed (nil if query successful). :faultcode is always returned 
	#  from the Salesforce org/SOQL query and RForce binding directly. :faultstring may be returned directly or created manually to be 
	#  more user friendly. Because of this, :faultcode should be the field used programatically to respond to faults
	def self.doQuery(org, soql, isRetry=false)
		if(ENV["user_#{org}"].nil?)
			return {:success => false, :fault => {:faultstring => "No credentials for org #{org}"}}
		end

		loginRes = Login(ENV["user_#{org}"], ENV["pass_#{org}"], org) if (!@@redis.exists("session_#{org}") || @@redis.ttl("session_#{org}") < 5 || !verifySID?(ENV["partner_#{org}"], org))
		if(!loginRes.nil? && !loginRes[:success])
			return {:success => false, :fault =>{:faultcode => loginRes[:faultcode], :faultstring => "Unable to login to Salesforce org"}}
		end

		binding = RForce::Binding.new ENV["partner_#{org}"], @@redis.get("session_#{org}")
		qres = binding.query :queryString => soql

		if(!qres.Fault.nil?)
			if(qres.Fault.faultcode.downcase.include?("invalid_session") && !isRetry)
				logputs "doQuery failed with fault #{qres.Fault.faultcode}, retrying..."
				Rollbar.info("Retry used", {:faultcode => qres.Fault.faultcode, :org => org, :soql => soql})
				return doQuery(org, soql, true)
			else
				Rollbar.error("SOQL Query Fault", {:faultcode => qres.Fault.faultcode, :faultstring => qres.Fault.faultstring, :org => org, :soql => soql})
				return {:success => false, :fault => {:faultcode => qres.Fault.faultcode, :faultstring => qres.Fault.faultstring}}
			end
		else
			return {:success => true, :records => qres.queryResponse.result.records, :size => qres.queryResponse.result[:size].to_i}
		end
	end

	##
	# Perform a specified SOQL UPDATE against a specified Salesforce org and return the results (if successful) or error/fault
	# codes if the update was unsuccessful. If the update failed, log the exception and stack to Rollbar for later diagnostics.
	# @param org [String] Org to query against
	# @param record [Hash] Record with updated values to save. Must include :Id key with object EID
	# @return [Hash] Hash of :success [Boolean] overall success of the operation,
	#  :fault [Hash] Fault details (faultcode, faultstring) if query failed (nil if query successful). :faultcode is always returned 
	#  from the Salesforce org/SOQL query and RForce binding directly. :faultstring may be returned directly or created manually to be 
	#  more user friendly. Because of this, :faultcode should be the field used programatically to respond to faults
	def self.doUpdate(org, record)
		if(record[:Id].nil?)
			return {:success => false, :fault => {:faultstring => "No EID in provided record"}}
		end

		if(ENV["user_#{org}"].nil?)
			return {:success => false, :fault => {:faultstring => "No credentials for org #{org}"}}
		end

		loginRes = Login(ENV["user_#{org}"], ENV["pass_#{org}"], org) if (!@@redis.exists("session_#{org}") || @@redis.ttl("session_#{org}") < 5 || !verifySID?(ENV["partner_#{org}"], org))
		if(!loginRes.nil? && !loginRes[:success])
			return {:success => false, :fault =>{:faultcode => loginRes[:faultcode], :faultstring => "Unable to login to Salesforce org"}}
		end

		binding = RForce::Binding.new ENV["partner_#{org}"], @@redis.get("session_#{org}")
		
		ures = binding.update :sObjects => record
		upRes = ures.updateResponse
		
		if(upRes.nil?)
			Rollbar.error("Salesforce Update Fault / updateResponse nil", {:response => ures.inspect, :org => org, :EID => record[:Id]})
			return {:success => false, :fault => {:faultcode => "Salesforce update failure", :faultstring => "Salesforce update failure"}}
		elsif(!upRes.result.success)
			Rollbar.error("Salesforce Update Fault", {:faultcode => upRes.result.errors[:statusCode], :faultstring => upRes.result.errors[:message], :org => org, :EID => record[:Id]})
			return {:success => false, :fault => {:faultcode => upRes.result.errors[:statusCode], :faultstring => "Salesforce update failure"}}
		else
			return {:success => true}
		end
	end

end
