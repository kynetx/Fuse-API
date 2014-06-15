
/* jshint undef: true, unused: true */
/* globals console:false, CloudOS:false  */
/* globals console, setTimeout, CloudOS, Fuse */

(function($)
{
    window['Fuse'] = {

        // development settings.
        VERSION: 0.1,

        defaults: {
            logging: false,  // false to turn off logging
	    production: false
        },

	get_rid : function(name) {

	    var rids = {
		"owner": {"prod": "b16x16",
			  "dev":  "b16x16"
			 },
		"fleet": {"prod": "b16x17",
			  "dev":  "b16x17"
			 },
		"vehicle": {"prod": "b16x9",
			    "dev":  "b16x9"
			   },
		"trips": {"prod": "b16x18",
			  "dev":  "b16x18"
			 },
		"fuel":  {"prod": "b16x20",
			  "dev":  "b16x20"
			 },
		"carvoyant":  {"prod": "b16x11",
			       "dev":  "b16x11"
			 }
	    };

	    return this.defaults.production ? rids[name].prod :  rids[name].dev;
	},

	// we'll retrieve the fleet and vehicle ECIs later and put them here...
	fleet_eci: "", 
	vehicles: [],
	vehicle_status: "",
	vehicle_summary: "",

        init: function(cb)
        {
	    cb = cb || function(){};
	    Fuse.log("Initializing...");
	    $.when(
		Fuse.get_profile(),
		Fuse.fleetChannel()
	    ).done(function(profile, eci){
		Fuse.log("Stored fleet channel", eci[0]);
		Fuse.log("Retrieved user profile", profile[0]);
		cb(profile[0], eci[0]);
		Fuse.log("Done initializing...");
	    }).fail(function(res){
		Fuse.log("Initialization failed...", res);
	    });
        },

        detect_type: function(o)
        {
            if (typeof o !== "object") return typeof o;

            if (o === null) return "null";

            var internal_class = Object.prototype.toString.call(o).match(/\[object\s(\w+)\]/)[1];
            return internal_class.toLowerCase();
        },

        log: function()
        {
            if (this.defaults.logging && console && console.log) {
		[].unshift.call(arguments, "Fuse:"); // arguments is Array-like, it's not an Array 
                console.log.apply(console, arguments);
            }
        },

	// ---------- profile ----------
        get_profile: function(cb)
        {
	    cb = cb || function(){};
            if (typeof Fuse.user === "undefined") {
                Fuse.log("Retrieving profile for user");
                return CloudOS.getMyProfile(function(profile)
                {
                    Fuse.user = profile;
                    if (typeof cb === "function") {
                        cb(Fuse.user);
                    }
                });
            } else {
                cb(Fuse.user);
		return null;
            }
        },

        save_profile: function(json, cb)
        {
            return CloudOS.updateMyProfile(json, cb);
        },

	// ---------- account ----------
	initAccount: function(attrs, cb, options)
        {
	    cb = cb || function(){};
	    options = options || {};
	    attrs = attrs || {};
            Fuse.log("Initializing account for user with attributes ", attrs);

            return CloudOS.raiseEvent("fuse", "bootstrap", {}, attrs, function(response)
            {
		// note that because the channel is create asynchronously, processing callback does
		// NOT mean the channel exists. 
                Fuse.log("account initialized");
		if(response.length < 1) {
		    throw "Account initialization failed";
		}
		cb(response);
            });
        },

	createCarvoyantAccount: function(attrs, cb, options)
        {
	    cb = cb || function(){};
	    options = options || {};
	    attrs = attrs || {};
            var fleet_channel = options.fleet_channel || Fuse.fleetChannel();
	    Fuse.log("Creating Carvoyant account for user with attributes ", attrs);

            return CloudOS.raiseEvent("carvoyant", "init_account", {}, attrs, function(response)
            {
                Fuse.log("Carvoyant account created");
		if(response.length < 1) {
		    throw "Carvoyant account creation failed";
		}
		cb(response);
            },
	    {"eci": fleet_channel
	    });
        },

	codeForToken: function(code, cb, options) 
	{
	    cb = cb || function(){};
	    options = options || {};
            Fuse.log("Retrieving access token");
		return CloudOS.skyCloud(Fuse.get_rid("owner"), "fleetChannel", {}, function(json) {
		    Fuse.fleet_eci = json.cid;
		    Fuse.log("Retrieved fleet channel", json);
		    cb(json);
		});
	},

	carvoyantOauthUrl: function(cb, options) 
	{
	    cb = cb || function(){};
	    options = options || {};
	    options.rid = "carvoyant";
            Fuse.log("Retrieving Carvoyant OAuth URL");
	    return Fuse.ask_fleet("carvoyantOauthUrl", Fuse.carvoyant_oauth_url, function(json) {
		          Fuse.carvoyant_oauth_url = json.url;
		          Fuse.log("URL: ", json);
			  cb(json);
  		       }, options);
	},

	// ---------- manage and use fleet pico ----------
        createFleet: function(attrs, cb, options)
        {
	    cb = cb || function(){};
	    options = options || {};
            Fuse.log("Creating fleet with attributes ", attrs);
            return CloudOS.raiseEvent("fuse", "need_fleet", {}, attrs, function(response)
            {
		// note that because the channel is create asynchronously, processing callback does
		// NOT mean the channel exists. 
                Fuse.log("Fleet created");
		if(response.length < 1) {
		    throw "Fleet creation failed";
		}
		cb(response);
            });
        },

        deleteFleet: function(cb, options)
        {
	    cb = cb || function(){};
	    options = options || {};
	    var fleet_channel = options.fleet_channel || Fuse.fleetChannel();
	    if(fleet_channel === null ) {
		throw "Fleet ECI is null; can't delete";
	    };
            var attrs = { "fleet_eci": fleet_channel };
            return CloudOS.raiseEvent("fuse", "delete_fleet", {}, attrs, function(response)
            {
                Fuse.log("Fleet deleted with ECI: " + fleet_channel);
		var fleet_channel = Fuse.fleetChannel(function(){}, {"force": true});
		if(response.length < 1) {
		    throw "Fleet deletion failed";
		}
                cb(response);
            });
        },

	fleetChannel: function(cb, options) 
	{
	    cb = cb || function(){};
	    options = options || {};
	    if (typeof Fuse.fleet_eci === "undefined" || Fuse.fleet_eci === "" || Fuse.fleet_eci === null || options.force) {
                Fuse.log("Retrieving fleet channel");
		return CloudOS.skyCloud(Fuse.get_rid("owner"), "fleetChannel", {}, function(json) {
		    Fuse.fleet_eci = json.eci;
		    Fuse.log("Retrieved fleet channel", json);
		    cb(json.eci);
		});
	    } else {
		cb(Fuse.fleet_eci);
		return Fuse.fleet_eci;
	    }
	},

	ask_fleet: function(funcName, cache, cb, options) {
	    cb = cb || function(){};
	    options = options || {};
	    var rid = options.rid || "fleet";
	    if (typeof cache === "undefined" 
	      || cache === "" 
	      || cache === null
	      || (typeof cache === "object" && typeof cache.length === "number" && cache.length < 1)
	      || options.force
	       ) {
                   Fuse.log("Calling " + funcName);
		   Fuse.fleetChannel(function(fc) {
		       Fuse.log("Using fleet channel ", fc);
   		       if(fc !== "none") {
			   return CloudOS.skyCloud(Fuse.get_rid(rid), funcName, {}, cb, {"eci": fc});
		       } else {
			   Fuse.log("fleet_eci is undefined, you must get the fleet channel first");
			   return null;
		       }
		   });
	       } else {
		   cb(cache);
		   return cache;
	       }
	},

	// tells the fleet to broadcast access tokens to the vehicles. 
	// should be done any time the access token is refreshed or a new vehicle is added
	configureVehicles: function(config, cb, options)
        {
	    cb = cb || function(){};
	    options = options || {};
	    var fleet_channel = options.fleet_channel || Fuse.fleetChannel();
	    if(fleet_channel === null ) {
		throw "Fleet channel is null; can't configure vehicles";
	    };
	    var attrs = config;
            return CloudOS.raiseEvent("fuse", "config_outdated", {}, attrs, function(response)
            {
                Fuse.log("Updated vehicle configurations");
		if(response.length < 1) {
		    throw "Vehicle configuration failed";
		}
                cb(response);
            },
	    {"eci": fleet_channel
	    } 
            );
        },



	vehicleChannels: function(cb, options){
	    cb = cb || function(){};
	    options = options || {};
            Fuse.log("Retrieving vehicles");
	    return Fuse.ask_fleet("vehicleChannels", Fuse.vehicles, function(json) {
		          Fuse.vehicles = json;
		          Fuse.log("Retrieved vehicles", json);
			  cb(json);
  		       }, options);
	},

	vehicleStatus: function(cb, options) {
	    cb = cb || function(){};
	    options = options || {};
	    return Fuse.ask_fleet("vehicleStatus", Fuse.vehicle_status, function(json) {
			Fuse.vehicle_status = json;
			Fuse.log("Retrieve vehicle status", json);
			cb(json);
  		       }, options);
	},

	vehicleSummary: function(cb, options) {
	    cb = cb || function(){};
	    options = options || {};
	    return Fuse.ask_fleet("vehicleSummary", Fuse.vehicle_summary, function(json) {
			Fuse.vehicle_summary = json;
			Fuse.log("Retrieve vehicle summary", json);
			cb(json);
  		       }, options);
	},

	// ---------- manage and use vehicle picos ----------
        createVehicle: function(name, photo_url, vin, deviceId, cb, options)
        {
	    cb = cb || function(){}; // prophilaxis
	    options = options || {};
	    var json = {"name": name,
			"photo": photo_url,
			"vin": vin,
			"deviceId": deviceId
		       };
	    Fuse.fleetChannel(function(fleet_channel) {
		if(fleet_channel === null ) {
		    throw "Fleet channel is null; can't add vehicle";
		};
		Fuse.log("Creating vehicle with attributes ", json);
		return CloudOS.raiseEvent("fuse", "need_new_vehicle", {}, json, function(response)
			{
			    // note that because the channel is create asynchronously, processing callback does
			    // NOT mean the channel exists. 
			    Fuse.log("Vehicle added");
			    cb(response);
			},
			{"eci": fleet_channel
			}
		      );
		});
        },

        deleteVehicle: function(vehicle_name, cb, options)
        {
	    cb = cb || function(){};
	    options = options || {};
	    Fuse.fleetChannel(function(fleet_channel){
		if(fleet_channel === null ) {
		    throw "Fleet channel is null; can't delete vehicle";
		};
		if(typeof vehicle_name === "undefined" || vehicle_name === null ) {
		    throw "Vehicle channel is null; can't delete vehicle";
		};
		var attrs = { "vehicle_name": vehicle_name };
		return CloudOS.raiseEvent("fuse", "delete_vehicle", {}, attrs, function(response)
					  {
					      Fuse.log("Fleet deleted with ECI: " + fleet_channel);
					      Fuse.vehicles = []; // reset so that the next call to vehicleChannels() is forced to update
					      if(response.length < 1) {
						  throw "Vehicle deletion failed";
					      }
					      cb(response);
					  },
					  {"eci": fleet_channel
					  } 
					 );
	    });
        },

	initializeVehicle: function(vehicle_channel, cb, options)
        {
	    cb = cb || function(){};
	    options = options || {};
	    if(typeof vehicle_channel === "undefined" || vehicle_channel === null ) {
		throw "Vehicle channel is null; can't initialize vehicle";
	    };
	    var attrs = {};
            return CloudOS.raiseEvent("fuse", "vehicle_uninitialized", {}, attrs, function(response)
            {
                Fuse.log("Initialized vehicle for: " + vehicle_channel);
		if(response.length < 1) {
		    throw "Vehicle initialization failed";
		}
                cb(response);
            },
	    {"eci": vehicle_channel
	    } 
            );
        },

	initCarvoyantVehicle: function(vehicle_channel, cb, options)
        {
	    cb = cb || function(){};
	    options = options || {};
	    if(typeof vehicle_channel === "undefined" || vehicle_channel === null ) {
		throw "Vehicle channel is null; can't update Carvoyant account for vehicle";
	    };
	    var attrs = {"label": options.label,
			 "mileage": options.mileage
			};

            return CloudOS.raiseEvent("carvoyant", "init_vehicle", attrs, {}, function(response)
            {
                Fuse.log("Initialized carvoyant account for vehicle: " + vehicle_channel);
		if(response.length < 1) {
		    throw "Vehicle initialization failed";
		}
                cb(response);
            },
	    {"eci": vehicle_channel
	    } 
            );
        },


	updateCarvoyantVehicle: function(vehicle_channel, cb, options)
        {
	    cb = cb || function(){};
	    options = options || {};
	    if(typeof vehicle_channel === "undefined" || vehicle_channel === null ) {
		throw "Vehicle channel is null; can't update Carvoyant account for vehicle";
	    };
	    var attrs = {"label": options.label,
			 "mileage": options.mileage,
			 "deviceId": options.deviceId
			};

            return CloudOS.raiseEvent("carvoyant", "init_vehicle", attrs, {}, function(response)
            {
                Fuse.log("Updated carvoyant account for  vehicle: " + vehicle_channel);
		if(response.length < 1) {
		    throw "Vehicle initialization failed";
		}
                cb(response);
            },
	    {"eci": vehicle_channel
	    } 
            );
        },



	updateVehicleDataCarvoyant: function(vehicle_channel, data_type, cb, options)
        {
	    cb = cb || function(){};
	    options = options || {};
	    var event_map = {"summary" : {"event" : "need_vehicle_data",
					  "attributes": []},
			     "status" : {"event":"need_vehicle_status",
					  "attributes": []},
			     "trip": {"event": "new_trip",
				      "attributes": ["tripId"]}
			    };
	    
	    if(typeof vehicle_channel === "undefined" || vehicle_channel === null ) {
		throw "Vehicle channel is null; can't update vehicle";
	    };
	    var attrs = {};
	    $.each(event_map[data_type].attributes,function(i,v){
		attrs[v] = options[v];
	    });
            return CloudOS.raiseEvent("fuse", event_map[data_type].event, {}, attrs, function(response)
            {
                Fuse.log("Updated vehicle data for: " + vehicle_channel);
		if(response.length < 1) {
		    throw "Vehicle update failed";
		}
                cb(response);
            },
	    {"eci": vehicle_channel
	    } 
            );
        },

	ask_vehicle: function(vehicle_channel, funcName, args, cache, cb, options) {
	    cb = cb || function(){};
	    options = options || {};
	    cache = cache || {};
	    var rid = options.rid || "vehicle";
	    if (typeof cache[vehicle_channel] === "undefined" 
	      || cache[vehicle_channel] === "" 
	      || cache[vehicle_channel] === null
	      || (typeof cache[vehicle_channel] === "object" && typeof cache[vehicle_channel].length === "number" && cache[vehicle_channel].length < 1)
	      || options.force
	       ) {
                Fuse.log("Calling " + funcName);
		if(vehicle_channel !== "none") {
		    return CloudOS.skyCloud(Fuse.get_rid(rid), funcName, args, cb, {"eci": vehicle_channel});
		} else {
		    Fuse.log("vehicle_channel is undefined, you must get the vehicle channel first");
		    return null;
		}
	    } else {
		Fuse.log("Using cached ")
		cb(cache[vehicle_channel]);
		return cache[vehicle_channel]
	    }
	},


	// ---------- Fuel ----------
	getFillup: function(vehicle_channel, cb, options) {
	    cb = cb || function(){};
	    options = options || {};
	    options.rid = "fuel";
	    
	    var args = options.key ? {"key": options.key} : {};

	    return Fuse.ask_vehicle(vehicle_channel, "fillup", args, null, function(json) {
			Fuse.log("Retrieve last fillup", json);
			cb(json);
  		       }, options);
	},


	recordFillUp: function(vehicle_channel, fillup_obj, cb, options)
        {
	    cb = cb || function(){};
	    options = options || {};
	    if(typeof vehicle_channel === "undefined" || vehicle_channel === null ) {
		throw "Vehicle channel is null; can't record fuel fillup for vehicle";
	    };
	    Fuse.requireParams({volume: fillup_obj.volume,
				unitPrice: fillup_obj.unitPrice,
				odometer: fillup_obj.odometer
			       });

            return CloudOS.raiseEvent("fuse", "new_fuel_purchase", {}, fillup_obj, function(response)
				      {
					  Fuse.log("Recorded fillup for vehicle: " + vehicle_channel);
					  if(response.length < 2) {
					      throw "Fuel fillup record failed for vehicle: "  + vehicle_channel;
					  }
					  cb(response);
				      },
				      {"eci": vehicle_channel
				      } 
            );
        },

	updateFillUp: function(vehicle_channel, fillup_obj, cb, options)
        {
	    cb = cb || function(){};
	    options = options || {};
	    if(typeof vehicle_channel === "undefined" || vehicle_channel === null ) {
		throw "Vehicle channel is null; can't record fuel fillup for vehicle";
	    };
	    Fuse.requireParams({volume: fillup_obj.volume,
				unitPrice: fillup_obj.unitPrice,
				odometer: fillup_obj.odometer,
				key: fillup_obj.key
			       });

            return CloudOS.raiseEvent("fuse", "updated_fuel_purchase", {}, fillup_obj, function(response)
				      {
					  Fuse.log("Updateded fillup for vehicle: " + vehicle_channel);
					  if(response.length < 1) {
					      throw "Fuel fillup update failed for vehicle: "  + vehicle_channel;
					  }
					  cb(response);
				      },
				      {"eci": vehicle_channel
				      } 
            );
        },

	deleteFillUp: function(vehicle_channel, key, cb, options)
        {
	    cb = cb || function(){};
	    options = options || {};
	    if(typeof vehicle_channel === "undefined" || vehicle_channel === null ) {
		throw "Vehicle channel is null; can't record fuel fillup for vehicle";
	    };
	    Fuse.requireParams({key: key});

	    var attrs = {"key": key};
            return CloudOS.raiseEvent("fuse", "unneeded_fuel_purchase", {}, attrs, function(response)
            {
                Fuse.log("Deleted fillup for vehicle: " + vehicle_channel);
		if(response.length < 1) {
		    throw "Fuel fillup record delete failed for vehicle: "  + vehicle_channel;
		}
                cb(response);
            },
	    {"eci": vehicle_channel
	    } 
            );
        },

	// ---------- trips ----------
	lastTrip: function(vehicle_channel, cb, options) {
	    cb = cb || function(){};
	    options = options || {};
	    options.rid = "trips";
	    
	    Fuse.last_trip = Fuse.last_trip || {};

	    var args = {};

	    return Fuse.ask_vehicle(vehicle_channel, "lastTrip", args, Fuse.last_trip, function(json) {
			Fuse.last_trip[vehicle_channel] = json;
			Fuse.log("Retrieve last trip", json);
			cb(json);
  		       }, options);
	},

	trips: function(vehicle_channel, start, end, cb, options) {
	    cb = cb || function(){};
	    options = options || {};
	    options.rid = "trips";
	    
	    var args = {"start": start,
			"end": end
		       };

	    return Fuse.ask_vehicle(vehicle_channel, "trips", args, null, function(json) {
			Fuse.log("Retrieve trips", json);
			cb(json);
  		       }, options);
	},

	icalSubscriptionUrl: function(vehicle_channel, cb, options) {
	    cb = cb || function(){};
	    options = options || {};
	    options.rid = "trips";
	    
	    var args = {};

	    return Fuse.ask_vehicle(vehicle_channel, "icalSubscriptionUrl", args, null, function(json) {
			Fuse.log("iCal subscription URL: ", json);
			cb(json);
  		       }, options);
	},
	
	updateTrip: function(vehicle_channel, trip_id, trip_name, trip_category, cb, options) {
	    cb = cb || function(){};
	    options = options || {};
	    if(typeof vehicle_channel === "undefined" || vehicle_channel === null ) {
		throw "Vehicle channel is null; can't record fuel fillup for vehicle";
	    };
	    if( typeof trip_id === "undefined" 
	      ){
		throw "Bad data; Trip ID is required: ";
	    }

	    var attrs  = {"tripId": trip_id,
		          "tripName": trip_name,
			  "tripCategory" : trip_category
			 };
            return CloudOS.raiseEvent("fuse", "trip_meta_data", {}, attrs, function(response)
            {
                Fuse.log("Updated trip for vehicle: " + vehicle_channel + " with ", attrs);
		if(response.length < 1) {
		    throw "Updating trip (" + trip_id + ") failed for vehicle: "  + vehicle_channel;
		}
                cb(response);
            },
	    {"eci": vehicle_channel
	    } 
            );
	},


	// ---------- subscriptions to device events ----------
	vehicleSubscriptions: function(vehicle_channel, cb, options) {
	    cb = cb || function(){};
	    options = options || {};
	    options.rid = "vehicle";
	    
	    Fuse.last_trip = Fuse.last_trip || {};

	    var args = {};
	    if(typeof options.subscription_type !== "undefined") {
		args.subscription_type = options.subscription_type;
	    }
	    if(typeof options.subscription_id !== "undefined") {
		args.subscription_id = options.subscription_id;
	    }

	    return Fuse.ask_vehicle(vehicle_channel, "vehicleSubscription", args, {}, function(json) {
			Fuse.log("Retrieve vehicle subscriptions", json);
			cb(json);
  		       }, options);
	},

	addSubscription: function(vehicle_channel, subscription_type, cb, options)
        {
	    cb = cb || function(){};
	    options = options || {};
	    if(typeof vehicle_channel === "undefined" || vehicle_channel === null ) {
		throw "Vehicle channel is null; can't add subscription for vehicle";
	    };
	    if( typeof subscription_type === "undefined" 
	      ){
		throw "Bad data; invalid subscription type: ", subscription_typej;
	    }

	    var attrs  = {"subscription_type": subscription_type,
			  "idempotent" : options.idempotent
			 };
            return CloudOS.raiseEvent("carvoyant", "new_subscription_needed", {}, attrs, function(response)
            {
                Fuse.log("Added new subscription ("+ subscription_type + ") for vehicle: " + vehicle_channel);
		if(response.length < 1) {
		    throw "Adding subscription (" + subscription_type + ") failed for vehicle: "  + vehicle_channel;
		}
                cb(response);
            },
	    {"eci": vehicle_channel
	    } 
            );
        },

	deleteSubscription: function(vehicle_channel, subscription_type, subscription_id, cb, options)
        {
	    cb = cb || function(){};
	    options = options || {};
	    if(typeof vehicle_channel === "undefined" || vehicle_channel === null ) {
		throw "Vehicle channel is null; can't delete subscription for vehicle";
	    };
	    if( typeof subscription_type === "undefined" 
             || typeof subscription_id === "undefined" 
	      ){
		throw "Bad params; subscription_type: " + subscription_type + ", subscription_id: " + subscription_id;
	    }
	    var attrs = {"subscription_type": subscription_type,
			 "subscription_id": subscription_id
			};
            return CloudOS.raiseEvent("fuse", "subscription_not_needed", {}, attrs, function(response)
            {
                Fuse.log("Deleted subscription (" + subscription_type +  ", " + subscription_id + ") for vehicle: " + vehicle_channel);
		if(response.length < 1) {
		    throw "Subscription delete failed (" + subscription_type +  ", " + subscription_id + ") for vehicle: " + vehicle_channel;
		}
                cb(response);
            },
	    {"eci": vehicle_channel
	    } 
            );
        },

	requireParams: function(params) {

	    if( typeof params === "undefined") {
		throw "Data data; undefined params";
	    }

	    $.each(params, function(k, v){
		if(typeof v === "undefined" || v === null ) {
		    throw "Data data; parameter undefined: " + k;
		};
	    });
	},

    };



})(jQuery);


