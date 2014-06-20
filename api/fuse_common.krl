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
	         convertToUTC, vehicleChannels,
	         skycloud
    }

    global {


      S3Bucket = function(){"k-fuse-01"};

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
	   p.put(["channel"],vehicle_ecis_by_name{[id,"eventChannel"]});
	}).values();
	res
      };



  }

}
