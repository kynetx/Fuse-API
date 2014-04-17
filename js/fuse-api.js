
/* jshint undef: true, unused: true */
/* global console:false, CloudOS:false  */
/* global console, CloudOS */

(function($)
{
    window['Fuse'] = {

        // development settings.
        VERSION: 0.1,

        defaults: {
            logging: false,  // false to turn off logging
	    production: false
        },

        owner_rid: function(){return this.defaults.production ? "b16x16" : "b16x16";},
        fleet_rid: function(){return this.defaults.production ? "b16x17" : "b16x17";},

	fleet_eci: "", // we'll retrieve the fleet ECI later and put it here for use...

        init: function(cb)
        {
	    cb = cb || function(){};
	    Fuse.log("Initializing...");
	    $.when(
		Fuse.get_profile(),
		Fuse.fleet_channel()
	    ).done(function(profile, eci){
		Fuse.log("Done initializing...");
		Fuse.log("Stored fleet channel", eci[0]);
		Fuse.log("Retrieved user profile", profile[0]);
		cb(profile[0], eci[0]);
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

	fleet_channel: function(cb) 
	{
	    cb = cb || function(){};
	    if (typeof Fuse.fleet_eci === "undefined" || Fuse.fleet_eci === "") {
                Fuse.log("Retrieving fleet channel");
		return CloudOS.skyCloud(this.owner_rid(), "fleetChannel", {}, function(json) {
		    Fuse.fleet_eci = json.cid;
		    Fuse.log("Retrieved fleet channel", json);
		    cb(json);
		});
	    } else {
		cb(Fuse.fleet_eci);
		return null;
	    }
	},

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
            Fuse.log("Updating profile: ", json);
            return CloudOS.raiseEvent("fuse", "should_update_user", json, {}, cb);
        },

        create_fleet: function(json, callback)
        {
            Fuse.log("creating fleet");
            //                this.log(json, {raw: true});
            Fuse.log("Create params ", json);
            // CloudOS.raiseEvent("fuse", "should_make_fleet", json, {}, function(response)
            // {
            //     Fuse.log("fleet created");
            //     if (typeof (callback) !== "undefined") {
            //         callback(response);
            //     }
            // });
        },

        get_fleet: function(id, callback, error_callback, retry)
        {

            Fuse.log("retrieving fleet ", id);
            var params = { "id": id };

	    var retries = 1;
	    retry = retry || 0;

            // CloudOS.skyCloud(this.Guard_Tour_API_RID, "fleet", params, function(json) {
	    // 	if (json.id !== id) {
	    // 	    Fuse.log("ID Mismatch! Asked for " + id + " and got " + json.id);
	    // 	    // try again
	    // 	    if (retry < retries) {
	    // 		Fuse.get_fleet(id, callback, error_callback, retry+1);
	    // 	    }
	    // 	} else {
	    // 	    Fuse.log("IDs match! Asked for " + id + " and got " + json.id);
	    // 	}
	    // 	if (typeof (callback) !== "undefined") {
            //         callback(json);
            //     }	
	    // }, error_callback);
        },

        update_fleet: function(updated_attrs, id, callback)
        {
            updated_attrs.id = id;
            // Fuse.log("Updating fleet with params ", params);
            // CloudOS.raiseEvent("fuse", "should_update_fleet", updated_attrs, {}, function(response)
            // {
            //     //                    Fuse.log(response, {raw:true});
            //     check_directive("Fleet", response, "didRequestFleetUpdate");

            //     // what if I want a callback even if I'm not testing? Therefore I'd rather check if callback
            //     // is defined, and if so then call it.
            //     if (typeof (callback) !== "undefined") {
            //         callback(response);
            //     }
            // });
        },

        delete_fleet: function(id, callback)
        {
            var params = { "id": id };
            // CloudOS.raiseEvent("fuse", "should_delete_fleet", params, {}, function(response)
            // {
            //     Fuse.log("Fleet deleted with ID: " + id);
            //     Fuse.log(response, { raw: true });
            //     if (typeof (callback) !== "undefined") {
            //         callback(response);
            //     }
            // });
        }



    };



})(jQuery);


