
# Releasing Fuse

## Rulesets

To release production versions of the code:

1. Run the following command in  the ```/api``` directory:

		util/create_release.pl -v <vn>

	This will create the ```/api/<vn>``` directory with the names given by the map in ```create_release.pl```

	You should expect a clean run with no errors or warnings. 

2. Do the same thing for fuse_keys.krl if you're releasing keys.

3. Copy all of the version files created above to AWS. Note that everything but the keys file should be on a publicly readable URL.

	The keys file should have a signed URL created for it and this is what gets registered (see below).

	```keys``` and ```rulesets``` are separate directories inside the resource to avoid confusing public and private rulesets. 

4. Use the following command to register the URLs from above on KRE:

		/cloudos_new/ruleset_registry/register.pl

	See the help information (```-?```) for parameters. The registration is controlled by the ```register-fuse-production.yml``` configuration file which is *not* checked into Github on purpose since it has sensative, signed URLs, passwords, etc.

	Be sure to register any *new* rulesets and delete any that went away.

8. Flush all new rulesets (```create_release.pl``` prints out the flush command)


## Joinfuse.com

5. Ensure that the latest version of ```CloudOS.js``` is on AWS in the appropriate place (```CloudOS_assets/js``` bucket)

6. Ensure that the latest version of ```fuse-api.js``` is on AWS in the approprite place (```Fuse_assets/js``` bucket)

7. Merge latest changes from ```fuse-login``` with Joinfuse.com is necessary.
	- You have to be careful to make sure that the merged changes are pointing to the production versions rather than github or other places.
	- Specifically, ensure that ```_layouts/app.html``` is pointing at the ```fuse-api.js``` file on AWS

		http://kibdev.kobj.net/ruleset/flush/v1_carvoyant_module_test.prod;v1_fuse_bootstrap.prod;v1_fuse_carvoyant.prod;v1_fuse_common.prod;v1_fuse_error.prod;v1_fuse_fleet.prod;v1_fuse_fleet_oauth.prod;v1_fuse_fuel.prod;v1_fuse_owner.prod;v1_fuse_maintenance.prod;v1_fuse_reports.prod;v1_fuse_trips.prod;v1_fuse_vehicle.prod;v1_fuse_keys.prod

