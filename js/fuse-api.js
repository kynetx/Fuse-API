
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
		    Fuse.fleet_eci = json.cid;
		    Fuse.log("Retrieved fleet channel", json);
		    cb(json);
		});
	    } else {
		cb(Fuse.fleet_eci);
		return Fuse.fleet_eci;
	    }
	},

	ask_fleet: function(funcName, cache, cb, options) {
	    cb = cb || function(){};
	    options = options || {};
	    if (typeof cache === "undefined" 
	      || cache === "" 
	      || cache === null
	      || (typeof cache === "object" && typeof cache.length === "number" && cache.length < 1)
	       ) {
                Fuse.log("Calling " + funcName);
		var fc = Fuse.fleetChannel();
		if(fc !== "none") {
		    return CloudOS.skyCloud(Fuse.get_rid("fleet"), funcName, {}, cb, {"eci": fc});
		} else {
		    Fuse.log("fleet_eci is undefined, you must get the fleet channel first");
		    return null;
		}
	    } else {
		cb(cache);
		return cache
	    }
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
			Fuse.vehicles = json;
			Fuse.log("Retrieve vehicle status", json);
			cb(json);
  		       }, options);
	},

	vehicleSummary: function(cb, options) {
	    cb = cb || function(){};
	    options = options || {};
	    return Fuse.ask_fleet("vehicleSummary", Fuse.vehicle_summary, function(json) {
			Fuse.vehicles = json;
			Fuse.log("Retrieve vehicle summary", json);
			cb(json);
  		       }, options);
	},

	// ---------- manage and use vehicle picos ----------
        createVehicle: function(name, photo_url, cb, options)
        {
	    cb = cb || function(){}; // prophilaxis
	    options = options || {};
	    var json = {"name": name,
			"photo": photo_url
		       };
	    var fleet_channel = options.fleet_channel || Fuse.fleetChannel();
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
        },

        deleteVehicle: function(vehicle_channel, cb, options)
        {
	    cb = cb || function(){};
	    options = options || {};
	    var fleet_channel = options.fleet_channel || Fuse.fleetChannel();
	    if(fleet_channel === null ) {
		throw "Fleet channel is null; can't delete vehicle";
	    };
	    if(typeof vehicle_channel === "undefined" || vehicle_channel === null ) {
		throw "Vehicle channel is null; can't delete vehicle";
	    };
            var attrs = { "vehicle_eci": vehicle_channel };
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
        },

	configureVehicle: function(vehicle_channel, config, cb, options)
        {
	    cb = cb || function(){};
	    options = options || {};
	    if(typeof vehicle_channel === "undefined" || vehicle_channel === null ) {
		throw "Vehicle channel is null; can't configure vehicle";
	    };
	    var attrs = config;
            return CloudOS.raiseEvent("fuse", "updated_vehicle_configuration", {}, attrs, function(response)
            {
                Fuse.log("Updated vehicle configuration for: " + vehicle_channel);
		if(response.length < 1) {
		    throw "Vehicle configuration failed";
		}
                cb(response);
            },
	    {"eci": vehicle_channel
	    } 
            );
        },

	setVehicleDataFromCarvoyant: function(vehicle_channel, config, cb, options)
        {
	    cb = cb || function(){};
	    options = options || {};
	    if(typeof vehicle_channel === "undefined" || vehicle_channel === null ) {
		throw "Vehicle channel is null; can't update vehicle";
	    };
	    var attrs = config;
            return CloudOS.raiseEvent("fuse", "need_vehicle_data", {}, attrs, function(response)
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

    };



})(jQuery);


