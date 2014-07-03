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
	         convertToUTC, vehicleChannels, fleet_photo, factory,
	         skycloud, allowedRids
    }

    global {

       // rulesets we need installed by type
       apps = {
               "core": [
                   "a169x625.prod",  // CloudOS Service
                   "a169x676.prod",  // PDS
                   "a16x161.prod",   // Notification service
                   "a169x672.prod",  // MyProfile
                   "a41x174.prod",   // Amazon S3 module
                   "a16x129.dev",    // SendGrid module
		   "b16x13.prod"     // Fuse errors
               ],
               "fleet": [
                   "b16x11.prod",   // fuse_carvoyant.krl
                   "b16x17.prod",   // fuse_fleet.krl
                   "b16x23.prod"    // fuse_fleet_oauth.krl
               ],
               "vehicle": [
                   "b16x9.prod",   // fuse_vehicle.krl
		   "b16x11.prod",  // fuse_carvoyant.krl
		   "b16x18.prod",  // fuse_trips.krl
		   "b16x20.prod",  // fuse_fuel.krl
 		   "b16x21.prod"   // fuse_maintenance.krl
               ],
               "unwanted": [ 
                   "a169x625.prod",
                   "a169x664.prod",
                   "a169x667.prod",
                   "a41x178.prod",
                   "a169x672.prod",
                   "a169x669.prod",
                   "a169x727.prod",
                   "a169x695.prod",
                   "b177052x7.prod"
               ]
      };

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

      fleet_photo = "https://dl.dropboxusercontent.com/u/329530/fuse_fleet_pico_picture.png";

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
            .delete(["name"])
            .delete(["photo"])
	}).values();
	res
      };

      // rids allowed to ask for tokens from fleet
      allowedRids = function() {
        ["b16x11", "b16x23", "b16x17"];
      }

  }

}
