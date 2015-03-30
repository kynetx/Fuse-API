ruleset fuse_common {
    meta {
        name "Fuse Common Decls"
        description <<
Common definitions
        >>
        author "PJW"

        use module a169x625  alias CloudOS
        use module a169x676  alias pds


	provides S3Bucket, namespace, find_pico_by_id, fuel_namespace, trips_namespace, maint_namespace,
	         convertToUTC, strToNum, vehicleChannels, fleet_photo, vehicle_photo, factory, returnChannel,
		 fleetChannel, fleetChannels, requiredRulesets,
	         skycloud, allowedRids, genAndStore, retrieveVal 
    }

    global {

      genAndStore = function() {
        stored_value = ent:testpset.klog(">>>> saved value >>>>> ");
        math:random(999).pset(ent:testpset).klog(">>>> setting ent:testpset with >>>>");
      }

      retrieveVal = function() {
        ent:testpset
      }

       // rulesets we need installed by type
       apps = {
               "core": [
                   "a169x625.prod",  // CloudOS Service
                   "a169x676.prod",  // PDS
                   "a169x672.prod",  // MyProfile
                   "a41x174.prod",   // Amazon S3 module
                   "a16x129.dev",    // SendGrid module
		   "b16x13.prod",    // Fuse errors
		   "b16x19.prod",    // Fuse common
		   "b16x31.prod"     // pico notification service
               ],
	       "owner_optional" :[
	       ],
               "fleet": [
                   "b16x11.prod",   // fuse_carvoyant.krl
                   "b16x17.prod",   // fuse_fleet.krl
                   "b16x23.prod"    // fuse_fleet_oauth.krl
               ],
	       "fleet_optional" :[
	       ],
               "vehicle": [
                   "b16x9.prod",   // fuse_vehicle.krl
		   "b16x11.prod",  // fuse_carvoyant.krl
		   "b16x18.prod",  // fuse_trips.krl
		   "b16x20.prod",  // fuse_fuel.krl
 		   "b16x21.prod"   // fuse_maintenance.krl
               ],
	       "vehicle_optional" :[
	       ],
               "unwanted": [ 
                   "a16x161.prod",   // Notification service
                   "a169x664.prod",
                   "a169x667.prod",
                   "a41x178.prod",
                   "a169x669.prod",
                   "a169x727.prod",
                   "a169x695.prod",
                   "b177052x7.prod"
               ]
      };

      requiredRulesets = function(type) {
        apps{type};
      }

      // only ruleset installs are specific to fuse. Generalize? 
      factory = function(pico_meta, parent_eci) {
	  pico_schema = pico_meta{"schema"};
          pico_role = pico_meta{"role"};
          pico = CloudOS:cloudCreateChild(parent_eci);
          pico_auth_channel = pico{"token"};
          remove_rulesets = CloudOS:rulesetRemoveChild(apps{"unwanted"}, pico_auth_channel);
          install_rulesets = CloudOS:rulesetAddChild(apps{"core"}, pico_auth_channel);
          installed_rulesets = 
             (pico_role.match(re/fleet/gi)) => CloudOS:rulesetAddChild(apps{"fleet"}, pico_auth_channel)
                                             | CloudOS:rulesetAddChild(apps{"vehicle"}, pico_auth_channel);
          {
             "schema": pico_schema,
             "role": pico_role,
             "authChannel": pico_auth_channel,
	     "installed_rulesets": installed_rulesets
          }
        };

      S3Bucket = function(){"k-fuse-01"};

      fleet_photo = "https://s3.amazonaws.com/Fuse_assets/img/fuse_fleet_pico_picture.png";
      vehicle_photo = "https://s3.amazonaws.com/Fuse_assets/img/orange+logo.png";

      namespace = function() {
        meta_id = "fuse-meta";
	meta_id    
      };

      find_pico_by_id = function(id) {
	picos = CloudOS:picoList();
	picos_by_id = picos.values().collect(function(x){x{"id"}}).map(function(k,v){v.head()});
	picos_by_id{id};
      };

      // used as string in fuse_fuel.krl for event filtering
      fuel_namespace = function() {
        namespace_id = "fuse-fuel";
	namespace_id    
      };


      trips_namespace = function() {
        namespace_id = "fuse-trips";
	namespace_id    
      };


     maint_namespace = function() {
        namespace_id = "fuse-maint";
	namespace_id    
     };

     convertToUTC = function(dt) {
       time:strftime(dt, "%Y%m%dT%H%M%S%z", {"tz":"UTC"}).klog(">>>>> convertToUTC() returning for #{dt} >>>>> ")
     };

     strToNum = function(s) {
       s.as("num") + 0
     };
 
     // TODO: reduce error loquaciousness once on production.
     skycloud = function(eci, mod, func, params) {
        cloud_url = "https://#{meta:host()}/sky/cloud/";
        response = http:get("#{cloud_url}#{mod}/#{func}", (params || {}).put(["_eci"], eci));

        status = response{"status_code"};

        error_info = {
          "error": "sky cloud request was unsuccesful


",
          "httpStatus": {
              "code": status,
              "message": response{"status_line"}
          }
        };

        response_content = response{"content"}.decode();
        response_error = (response_content.typeof() eq "hash" && response_content{"error"}) => response_content{"error"} | 0;
        response_error_str = (response_content.typeof() eq "hash" && response_content{"error_str"}) => response_content{"error_str"} | 0;
        error = error_info.put({"skyCloudError": response_error, "skyCloudErrorMsg": response_error_str, "skyCloudReturnValue": response_content});
        is_bad_response = (response_content.isnull() || response_content eq "null" || response_error || response_error_str);

        // if HTTP status was OK & the response was not null and there were no errors...
        (status eq "200" && not is_bad_response) => response_content | error
     };


     //  Only works when executed in a fleet pico 
     // this is complicated cause we want to return the subscription channel for the vehicle, not the _LOGIN channel
     vehicleChannels = function() {

        picos = CloudOS:picoList() || {}; // tolerate lookup failures

	// the rest of this is to return subscription ECIs rather than _LOGIN ECIs. Ought to be easier. 
        vehicle_ecis = CloudOS:subscriptionList(namespace(),"Vehicle")
                    || [];   

        // collect returns arrays as values, and we only have one, so map head()
        vehicle_ecis_by_name = vehicle_ecis.collect(function(x){x{"channelName"}}).map(function(k,v){v.head()});

	res = picos.map(function(k,p){
	   id = p{"id"};
	   p.put(["channel"],vehicle_ecis_by_name{[id,"eventChannel"]})
            .put(["picoId"], id)
	    .delete(["id"])
            .delete(["name"])
            .delete(["photo"])
	}).values();
	res
      };

      // only works for vehicle!!  
      fleetChannels = function () {

        chans = CloudOS:subscriptionList(namespace(),"Fleet").pick("$..eventChannel", true).klog(">>> Fleet Channels >>> "); 
	chans.length() > 0 => chans
	                    | [ pds:get_item(namespace(),"fleet_channel") ] // if we can't find subscription use the one passed

      };

      // only works for vehicle!!  
      fleetChannel = function () {
          CloudOS:subscriptionList(namespace(),"Fleet").head().pick("$.eventChannel")
         ||
          pds:get_item(namespace(),"fleet_channel") // if we can't find subscription use the one passed
      };


      // rids allowed to ask for tokens from fleet
      allowedRids = function() {
        ["b16x11", "b16x23", "b16x17"];
      }


  }

  rule check_pico_config {
    select when fuse pico_config

    pre {

      about_me = pds:get_items(namespace()).klog(">>> about me >>>");
      my_role = about_me{"schema"}.lc();

      pico_auth_channel = meta:eci();

      // rulesets
      remove_rulesets = CloudOS:rulesetRemoveChild(apps{"unwanted"}, pico_auth_channel);
      core_rulesets = CloudOS:rulesetAddChild(apps{"core"}, pico_auth_channel);
      installed_rulesets = CloudOS:rulesetAddChild(apps{my_role}, pico_auth_channel);

      // picos
      picos = CloudOS:picoList()
                 .defaultsTo([])
		 .klog(">> this pico's picos >>>")
		 ; 

    }


  }

}
