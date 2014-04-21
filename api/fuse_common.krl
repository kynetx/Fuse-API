ruleset fuse_common {
    meta {
        name "Fuse Common Decls"
        description <<
Common definitions
        >>
        author "PJW"

	provides S3Bucket, namespace, find_pico_by_id
    }

    global {


      S3Bucket = function(){"k-fuse-01"};

      namespace = function(type) {
        meta_id = "fuse-meta";
	meta_id    
      };

      find_pico_by_id = function(id) {
	picos = CloudOS:picoList();
	picos_by_id = picos.values().collect(function(x){x{"id"}}).map(function(k,v){v.head()});
	picos_by_id{id};
      };



    }

}
