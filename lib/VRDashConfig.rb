##
# Copyright (c) 2016, salesforce.com, inc.
# All rights reserved.
# Licensed under the BSD 3-Clause license. 
# For full license text, see LICENSE.txt file in the repo root  or https://opensource.org/licenses/BSD-3-Clause
##

##
# VRDashConfig is the parent class for custom {DashConfig}s.
#
# VRDashConfig subclasses must define vrdash_key, which is a custom key unique to the {DashConfig}. They can optionally
# declare vrdash_settings which are custom settings implemented by the dash.
#
# VRDashConfig subclasses must finally define a generate() method which is what will be invoked when the dash is used and returns
# panels and statblocks. generate() takes in four parameters - the custom settings implemented for this VRDashConfig, the User ID
# of the user running the dashboard, the geo the user is currently viewing, and whether data should be cached (if implemented).
class VRDashConfig
	class << self

		def inherited(dash)
			dashes << dash
		end

		def dashes
			@dashes ||= []
		end

		def vrdash_key(key=nil)
			@vrdash_key = key.to_s if !key.nil?
			@vrdash_key ||= self.key
		end

		def vrdash_name(name=nil)
			@vrdash_name = name.to_s if !name.nil?
			@vrdash_name ||= self.name
		end

		def vrdash_settings(settings=nil)
			@vrdash_settings = settings if !settings.nil?
			@vrdash_settings ||= {}
		end

		def each(&block)
			dashes.each do |member|
				block.call(member)
			end
		end

		def getByKey(key)
			dashes.each do |dash|
				if(dash.vrdash_key == key)
					return dash
				end
			end

			return nil
		end

		##
		# Called to generate panels and stat blocks when this dashboard is requested by a user.
		# @param dc_settings [Hash <String => Object>] Current values of custom settings implemented by this Dashboard
		# @param uid [Integer] UID of {User} requesting the dashboard
		# @param geo [Object] Integer(s) of Geo user is currently set to view. Will either be an Integer or array of Integers.
		#  Note that this can be used without parsing/modification in database calls, e.g. application.geo => geo.
		# @param cache [Boolean] Passed boolean to override cache use, if you choose to implement it. If true, use cache.
		# @return Hash of :success (Boolean) and :generatedDash (Array<Array<Hash>,Array<Hash>>). :generatedDash[0] is an Array
		#  of Hashes, each representing one panel to display on the Dashboard. Each of these hashes should include the following keys:
		#  :title (String, title of panel), :color (String, color of panel chosen from primary (blue), success (green), warning (yellow), danger (red)),
		#  :records (Array of Hashes representing records that should be displayed in the panel. Each hash is made up of :app and :test which 
		#  contain the Application and Test object for the row, respectively. :test can be nil), :maxwks (Integer, number of weeks at which a record
		#  should be highlighted as overdue), and :zerotext (String to display if there are no records for the panel). The key :fetch_time can also 
		#  be included with a String representing the time this data was pulled from an external system, if you have implemented caching. :generatedDash[1] is
		#  an Array of Hashes, each representing one stat box to display on the Dashboard. This Object can also be nil to not display stat boxes. Each Hash
		#  in the Array should contain keys :icon (String - Font Awesome icon ID to use), :text (String, text to use as label), :value (Integer or Float value
		#  to display in statbox), :color (String, color of stat box using same values as panels).
		def generate(dc_settings, uid, geo=GEO::USA, cache=true)
			raise "NotImplemented"
		end
	end

	delegate :vrdash_key, to: :class
	delegate :vrdash_name, to: :class
	delegate :vrdash_settings, to: :class

end