
/* jshint undef: true, unused: true */
/* globals console:false, CloudOS:false  */
/* globals console, CloudOS, Fuse */

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
	vehicles: "",
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

	ask_fleet: function(funcName, cache, cb) {
	    cb = cb || function(){};
	    if (typeof cache === "undefined" || cache === "") {
                Fuse.log("Calling " + funcName);
		if(Fuse.fleet_eci !== "none") {
		    return CloudOS.skyCloud(Fuse.get_rid("fleet"), funcName, {}, cb, {"eci": Fuse.fleet_eci});
		} else {
		    Fuse.log("fleet_eci is undefined, you must get the fleet channel first");
		    return null;
		}
	    } else {
		cb(cache);
		return cache
	    }
	},

	vehicleChannels: function(cb){
	    return Fuse.ask_fleet("vehicleChannels", Fuse.vehicles, function(json) {
			Fuse.vehicles = json;
			Fuse.log("Retrieve vehicle channels", json);
			cb(json);
  		       });
	},

	vehicleStatus: function(cb) {
	    return Fuse.ask_fleet("vehicleStatus", Fuse.vehicle_status, function(json) {
			Fuse.vehicles = json;
			Fuse.log("Retrieve vehicle status", json);
			cb(json);
  		       });
	},

	vehicleSummary: function(cb) {
	    return Fuse.ask_fleet("vehicleSummary", Fuse.vehicle_summary, function(json) {
			Fuse.vehicles = json;
			Fuse.log("Retrieve vehicle summary", json);
			cb(json);
  		       });
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

	// ---------- manage fleet pico ----------
        createFleet: function(json, callback)
        {
            Fuse.log("Creating fleet with attributes ", json);
            return CloudOS.raiseEvent("fuse", "need_fleet", {}, json, function(response)
            {
		setTimeout(function(){
		    var fleet_channel = Fuse.fleetChannel(function(){}, {"force": true});
                    Fuse.log("Fleet created with channel ", fleet_channel);
                    if (typeof (callback) !== "undefined") {
			callback(response);
                    }},
		    3000); // wait three seconds for the subscription to propagate. Not ideal...
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
            return CloudOS.raiseEvent("fuse", "delete_fleet", {}, attrs, function(json)
            {
                Fuse.log("Fleet deleted with ECI: " + fleet_channel);
		var fleet_channel = Fuse.fleetChannel(function(){}, {"force": true});
                cb(json);
            });
        }



    };



})(jQuery);


