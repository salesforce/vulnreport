##
# Copyright (c) 2016, salesforce.com, inc.
# All rights reserved.
# Licensed under the BSD 3-Clause license. 
# For full license text, see LICENSE.txt file in the repo root  or https://opensource.org/licenses/BSD-3-Clause
##

require 'rubygems'
require 'data_mapper'
require_relative '../lib/dataMapperMakeDirty'
require 'pg'
require 'dm-postgres-adapter'
require 'rack/utils'

#Load in environment vars from DotEnv here too incase we're running just schema from IRB
require 'dotenv'
Dotenv.load

DataMapper.setup(:default, ENV['DATABASE_URL'])

#Ensure this is first as some defaults in the models require it
require './models/enums'
Dir["models/*.rb"].each {|model| require_relative model.split('/').last.split('.').first}

DataMapper.finalize
DataMapper.auto_upgrade!