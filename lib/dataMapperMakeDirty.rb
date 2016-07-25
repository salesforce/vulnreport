##
# Copyright (c) 2016, salesforce.com, inc.
# All rights reserved.
# Licensed under the BSD 3-Clause license. 
# For full license text, see LICENSE.txt file in the repo root  or https://opensource.org/licenses/BSD-3-Clause
##

require 'data_mapper'

#Reopen DataMapper::Resource
module DataMapper
	module Resource

		#Explicitly mark all given attributes of a DM Resource as dirty to force save.
		# Useful for Object properties.
		def make_dirty(*attributes)
			if attributes.empty?
				return
			end
			unless self.clean?
				self.save
			end
			dirty_state = DataMapper::Resource::PersistenceState::Dirty.new(self)
			attributes.each do |attribute|
				property = self.class.properties[attribute]
				dirty_state.original_attributes[property] = nil
				self.persistence_state = dirty_state
			end
		end

	end
end