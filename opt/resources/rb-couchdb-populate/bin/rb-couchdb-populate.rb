#!/usr/lcal/rvm/rubies/ruby-2.2.0/bin/ruby

# Author: Gabriel Prestes
# Created: 2015-02-04
# Last Modified: 2015-02-05
# Description: Populate Couchdb via POST JSON
# Version: 0.1

# Wishlist
#
# 1 - import task structure
# 2 - verify that the document exists and if so update it

require 'yaml'
require 'rubygems'
require 'net/http'

# --- APPLICATION CLASSES --- #

module Couch

        class Server

                def initialize(host, port, options = nil)

                        @host = host
                        @port = port
                        @options = options

                end

                def delete(uri)

                        request(Net::HTTP::Delete.new(uri))

                end

                def get(uri)

                        request(Net::HTTP::Get.new(uri))

                end


                def put(uri, json)

                        req = Net::HTTP::Put.new(uri)
                        req["content-type"] = "application/json"
                        req.body = json
                        request(req)

                end

                def post(uri, json)

                        req = Net::HTTP::Post.new(uri)
                        req["content-type"] = "application/json"
                        req.body = json
                        request(req)

                end

                def request(req)

                        res = Net::HTTP.start(@host, @port) { |http|http.request(req) }
                        unless res.kind_of?(Net::HTTPSuccess)
                        handle_error(req, res)

                        end

                        res

                end

                private

                def handle_error(req, res)

                        e = RuntimeError.new("#{res.code}:#{res.message}\nMETHOD:#{req.method}\nURI:#{req.path}\n#{res.body}")

                end

        end

end

# --- CONTROL FUNCTIONS --- #

def load_parameter(value)

        props = YAML.load_file(File.join(File.dirname(__FILE__), '../lib/program-conf.yml'))

        temp = props[value]

        return temp

end

def write_error_log(value)

        error_log = "#{$PATH}/log/rb-couchdb-populate-error.log"

        f = File.new(error_log, "w+")
        f.write("#{value}\n")
        f.close

end

def checkout_monitor(value)

        error_log = "#{$PATH}/log/rb-couchdb-populate-error.log"
        monitor = "#{$PATH}/var/rb-couchdb-populate.mon"

        if value == 0 || value == 1

                f = File.new(monitor, "w+")
                f.syswrite(value)
                f.close

        else

                if  File.exist?(error_log) == true

                        f = File.new(monitor, "w+")
                        f.syswrite(1)
                        f.close
                        return 1

                else

                        f = File.new(monitor, "w+")
                        f.syswrite(0)
                        f.close

                end

        end

        return 0

end

def pid_control(value)

        pid = "#{$PATH}/var/rb-couchdb-populate.pid"

        if value == 0

                if  File.exist?(pid) == true

                        return 1

                else

                        return 0

                end

        elsif value == 1

                f = File.new(pid, "w+")
                f.write(@pid)
                f.close
                return 0

        else

                File.delete(pid)

        end

end

# --- APPLICATION FUNCTIONS --- #

def connection_test

	dbhost = load_parameter 'dbhost'
        dbport = load_parameter 'dbport'
        dbname = load_parameter 'dbname'

        puts "| Test database connection > #{dbname} |\n"

        server = Couch::Server.new(dbhost, dbport)
        res = server.get("/#{dbname}")
        json = res.body

        if ( json =~ /.*doc_count.*/ )

		return 0

	else 
	
		return 1

        end

end

def parse_manifest(value)

	value = value.chomp

	puts "| Parse file #{value} |\n"

	file = `cat #{value}`
		
	nodeold=0
	classes=""

	file.each_line {|line|

		if line =~ /node \'(.+)\' {/ 

			nodenew = $1
			
			if nodenew !~ /#{nodeold}/ and nodeold != 0

				if get_from_couch(nodeold) == false

					puts "| Import node #{nodeold} to CouchDB |\n"

					classes = classes.chop
					f = File.new("#{$PATH}/var/input-#{nodeold}.json", "w+")
					f.write("{\"classes\" : \"#{classes}\" }")
					f.close
	
					classes=""
					import_to_couch(nodeold)
	
				else 

					puts "| Node #{nodeold} already exists in CouchDB |\n"
					classes=""

                        	end		

			end

			nodeold = nodenew

		end 

		if line =~ /class{'(.+)':}/ || line =~ /include (.*) }/ || line =~ /include (.*)$/

				classes.concat("#{$1},")

		end 

        }

	if get_from_couch(nodeold) == false

        	puts "| Import node #{nodeold} to CouchDB |\n"

                classes = classes.chop
                f = File.new("#{$PATH}/var/input-#{nodeold}.json", "w+")
                f.write("{\"classes\" : \"#{classes}\" }")
                f.close

                classes=""
                import_to_couch(nodeold)

	else

        	puts "| Node #{nodeold} already exists in CouchDB |\n"

	end

end

def get_from_couch(value)

        dbhost = load_parameter 'dbhost'
        dbport = load_parameter 'dbport'
        dbname = load_parameter 'dbname'

        server = Couch::Server.new(dbhost, dbport)
        res = server.get("/#{dbname}/#{value}")
        json = res.body

        if ( json =~ /.*#{value}.*/ )

                return true

        else

                return false

        end

end

def import_to_couch(value)

        dbhost = load_parameter 'dbhost'
        dbport = load_parameter 'dbport'
        dbname = load_parameter 'dbname'

        server = Couch::Server.new(dbhost, dbport)

	mode = "r+"
	file = File.open("#{$PATH}/var/input-#{value}.json", mode)
	doc = file.read
	file.close

	server.put("/#{dbname}/#{value}", doc)

end

# --- GLOBAL VARS --- #

$DATE = Time.new
$PATH = load_parameter 'path'
$OK = 0
$FAIL = 1
$CHECK = 3
$IS_RUNNING = 0
$START = 1
$STOP = 2

# --- MAIN FUNCTION --- #

def main

        puts "| Starting agent Current Time : " + $DATE.inspect + " |\n"

        if pid_control($IS_RUNNING) == 1

                puts "| Aborted - Program running |\n"
		write_error_log("| Aborted - Program running |\n")
                checkout_monitor($FAIL)
                exit

        else

                pid_control($START)

        end

        if connection_test() == 0 

		puts "| Connection PASS |\n"

	else
	
		puts "| Connection FAIL |\n"
		write_error_log("| Connection FAIL |\n")
		checkout_monitor($FAIL)
		exit

	end

	puppetdir = load_parameter 'puppetdir'
	puppetfile = load_parameter 'puppetfile'

	if Dir.exists?("#{puppetdir}") == true

		puts "| Directory #{puppetdir} exist |\n"

		filepoplist = `find #{puppetdir}/* -type f -name #{puppetfile} -exec ls {} \\;`

		filepoplist.each_line {|file|

			parse_manifest(file)

		}

	else 

		puts "| Directory #{puppetdir} not exist |\n"
		write_error_log("| Directory #{puppetdir} not exist |\n")
		checkout_monitor($FAIL)
		exit

	end	

        checkout_monitor($CHECK)

        pid_control($STOP)

        puts "| OK - Program end with success |\n"

end

main
