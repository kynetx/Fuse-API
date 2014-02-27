ruleset fuse_main {
    meta {
        name "Fuse API Main"
        description <<
            This is the master ruleset that manages, provides, and updates all things related to fuse. According to Ben,
        it is the bringer of all happiness.
    >>
    author "AKO & EDO & BEN & PHIL"
    logging off

    provides fuse_get_vehicle_list, fuse_get_trips, fuse_get_vehicle_location,
             fuse_get_vehicle_maintenance, fuse_get_vehicle_overview

    use module b16x10 alias fuse_keys

    use module a169x676 alias pds
    use module a41x220  alias maintenance
    use module a41x174 alias AWSS3
        with AWSKeys = keys:aws()
    }

    global {
        S3Bucket = "k-mycloud";

        fuse_api_get_vehicle_trips = function() {
            carvoyant_config_data = pds:get_items("carvoyant");
            device_id = carvoyant_config_data{"deviceID"};
            api_key = carvoyant_config_data{"apiKey"};
            secret_token = carvoyant_config_data{"secToken"};

            http:get(carvoyant_trip_url(device_id), {
                "credentials": {
                    "username": api_key,
                    "password": secret_token,
                    "realm": "Carvoyant API",
                    "netloc": "dash.carvoyant.com:443"
                },
                "params": {
                    "sortOrder": "desc"
                }
            })
        };

        fuse_get_trips = function() {

            this2that:transform(pds:get_items("vehicleTrips").values(), {
                "path": ["startTime"],
                "reverse": 1,
                "compare": "datetime"
            }, {
                "limit": 20
            })
        };

        fuse_get_vehicle_overview = function() {
            vehicle_info = pds:get_item("vehicle", "general");
            vehicle_raw = pds:get_items("vehicleRaw");
            {
                "name": vehicle_info{"name"},
                "status": vehicle_info{"status"},
                "location": {
                    "latitude": vehicle_info{"latitude"},
                    "longitude": vehicle_info{"longitude"}
                },
                "odometer": vehicle_raw{["GEN_ODOMETER", "translatedValue"]},
                "batteryVoltage": vehicle_raw{["GEN_VOLTAGE", "translatedValue"]},
                "fuelLevel": vehicle_raw{["GEN_FUELLEVEL", "translatedValue"]},
                "speed": vehicle_raw{["GEN_SPEED", "translatedValue"]}
            }
        }

        // --------------------------------------------
        fuse_get_vehicle_list = function() {

            myECI = meta:eci();
            // Get list of mci media
            esl = 'https://' + meta:host() + '/sky/cloud/' +
            'a169x667/getThings?&_eci=' + myECI;
            r = (myECI) => http:get(esl) | "none";

            // Determine status of request
            status_result = (myECI) => (r{"status_code"} eq "200") => true | false | false;
            status = { "status" : status_result};

            // Harvest content if http status is ok
            content = (status_result) => r{"content"}.decode() | {};

            vehicleList = content.filter(function(vehicleKey, vehicleValue) {
                (vehicleValue{["mySchemaName"]} eq "Vehicle")
            });

            // Convert results to array
            resultList = vehicleList.keys().map(function(vehicle_key) {
                vehicleName = content{[vehicle_key, "myProfileName"]} || "No Name";
                vehiclePhoto = content{[vehicle_key, "myProfilePhoto"]};
                vehicleChannel = content{[vehicle_key, "authChannel"]};
                {
                    "vehicleName"    : vehicleName,
                    "vehiclePhoto"   : vehiclePhoto,
                    "vehicleChannel" : vehicleChannel
                }
            });

            // Build response
            resultList
        };

        
        fuse_get_vehicle_location = function() {
            pds: get_item("vehicle", "location")
        };

        fuse_api_latest_data_url = function(vehicle_id) {
            "https://dash.carvoyant.com/api/vehicle/"+ vehicle_id +"/dataSet"
        };

        fuse_api_get_vehicle_location = function() {
            carvoyant_config_data = pds:get_items("carvoyant");
            device_id = carvoyant_config_data{"deviceID"};
            api_key = carvoyant_config_data{"apiKey"};
            secret_token = carvoyant_config_data{"secToken"};

            http:get(fuse_api_latest_data_url(device_id), {
                "credentials": {
                    "username": api_key,
                    "password": secret_token,
                    "realm": "Carvoyant API",
                    "netloc": "dash.carvoyant.com:443"
                },
                "params": {
                    "key": "GEN_WAYPOINT",
                    "sortOrder": "desc",
                    "searchLimit": "1"
                }
            })
        };

			// --------------------------------------------
			// https://cs.kobj.net/sky/cloud/a369x205/fuse_get_vehicle_maintenance?_eci=7BD0B300-7DDF-11E2-AB3A-B9D7E71C24E1
			fuse_get_vehicle_maintenance = function() {
			  maintenance:get_all()
			};

    }

    rule update_trips {
        select when fuse update_trips
        {
            noop();
        }
    }

    rule update_trip_tags {
        select when fuse new_trip_tags
        pre {
            trip_to_update = event:attr("trip_to_update");
            new_tags = event:attr("tags");
        }
        {
            send_directive("json") with data = {"success": true};
        }
        fired {
            raise pds event updated_data_available
             with namespace = "vehicleTrips"
             and  keyvalue = trip_to_update
             and  value = {"tags": new_tags}
             and  _api = "sky";
        }
    }

    // ------------------------------------------------------------------------
    rule CloudOS_RESTish_UpdateProfile_Photo {
        select when web submit "profileUpdate.post"
        pre {
            myECI     = meta:eci();
            thisRID   = meta:rid();
            imgSource = event:attr("myProfilePhoto");
            evtAttrs  = event:attrs();

            imgIsNew  = imgSource.match(re/^data:image/);
            imgName   = "#{thisRID}/#{myECI}.img";
            seed      = math:random(100000);
            imgURL    = (imgIsNew) => "https://s3.amazonaws.com/#{S3Bucket}/#{thisRID}/#{myECI}.img?q=#{seed}" | imgSource;
            imgValue  = (imgIsNew) => this2that:base642string(AWSS3:getValue(imgSource)) | "none";
            imgType   = (imgIsNew) => AWSS3:getType(imgSource) | "none";
            neuAttrs  = evtAttrs.put({ "myProfilePhoto" : imgURL });
        }
        if (imgIsNew) then {
            AWSS3:upload(S3Bucket, imgName, imgValue)
                with object_type = imgType;
        }
        always {
            raise pds event new_profile_item_available
            attributes neuAttrs;
        }
    }

    // ------------------------------------------------------------------------
    rule CloudOS_RESTish_UpdateProfile {
        select when web submit "profileUpdate.post"
        pre {
            myProfileName = event:attr("myProfileName");
            mHash = {
                'name' : myProfileName
            };
            mJSON = mHash.encode();
        }
        {
            send_raw("application/json")
                with content = mJSON;
        }
    }

    rule update_vehicle_location {
        select when fuse update_vehicle_location
        pre {
            vehicle_location = fuse_api_get_vehicle_location().pick("$.content").decode().pick("$.dataSet[0].datum[0].value").split(re/,/);
            vehicle_latitude = vehicle_location[0];
            vehicle_longitude = vehicle_location[1];
        }
        {
            noop();
        }
        fired {
            raise pds event new_data_available
                with namespace = "vehicle"
                and keyvalue = "location"
                and value = {
                        "latitude":vehicle_latitude,
                        "longitude":vehicle_longitude
                    }
                and _api = "sky";

            //schedule fuse event "update_vehicle_location" at time:add(time:now(), {"minutes" : 1});
        }
    }
}
