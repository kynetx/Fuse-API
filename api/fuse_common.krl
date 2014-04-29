ruleset fuse_common {
    meta {
        name "Fuse Common Decls"
        description <<
Common definitions
        >>
        author "PJW"

        use module a169x625  alias CloudOS
        use module a169x676  alias pds


	provides S3Bucket, namespace, find_pico_by_id, fuel_namespace, trips_namespace, maint_namespace
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



    }

}
