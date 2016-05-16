//Office 365 Simple Menu
//https://github.com/spjeff/spadmin/o365-simple-menu

(function () {
		
	//hide site feature
	function hideSPFeature(name) {
		$('h3.ms-standardheader:contains("' + name + '")').parent().parent().parent().parent().parent().parent().remove();
	};

	//URL contains expression
	function urlContains(expr) {
		return document.location.href.indexOf(expr) > 0;
	};

	//conditional hide
	$(document).ready(function() {
		
		if (!urlContains('skip')){
			//Web Features
			if (urlContains('ManageFeatures.aspx') && !urlContains('Scope=Site')) {
				//hide rows
				var features = ['Access App',
								'Announcement Tiles',
								'Community Site Feature',
								'Duet Enterprise - SAP Workflow',
								'Duet Enterprise Reporting',
								'Duet Enterprise Site Branding',
								'Getting Started with Project Web App',
								'Project Functionality',
								'Project Proposal Workflow',
								'Project Web App Connectivity',
								'SAP Workflow Web Parts',
								'SharePoint Server Publishing'
								];
				$.each(features, function(i, feature) {
					hideSPFeature(feature);
				});
				
				//remove alternating row color
				$('td.ms-featurealtrow').removeClass('ms-featurealtrow');
			}
			
			
			//Site Features
			if (urlContains('ManageFeatures.aspx?Scope=Site')) {
				//hide rows
				var features = ['Content Type Syndication Hub',
								'Custom Site Collection Help',
								'Cross-Site Collection Publishing',
								
								'Duet End User Help Collection',
								'Duet Enterprise Reports Content Types',
								
								'In Place Records Management',
								'Library and Folder Based Retention',
								'Limited-access user permission lockdown mode',
								
								'Project Server Approval Content Type',
								'Project Web App Permission for Excel Web App Refresh',
								'Project Web App Ribbon',
								'Project Web App Settings',
								
								'Publishing Approval Workflow',
								
								'Sample Proposal',
								'Search Engine Sitemap',
								'SharePoint 2007 Workflows',
								'SharePoint Server Publishing Infrastructure',
								
								'Site Policy'
								];
				$.each(features, function(i, feature) {
					hideSPFeature(feature);
				});
				
				//remove alternating row color
				$('td.ms-featurealtrow').removeClass('ms-featurealtrow');
			}
		
			//Site Settings
			if (urlContains('settings.aspx')) {
				//hide links
				var links = ['#ctl00_PlaceHolderMain_SiteCollectionAdmin_RptControls_AuditSettings',
							'#ctl00_PlaceHolderMain_SiteCollectionAdmin_RptControls_SharePointDesignerSettings',
							'#ctl00_PlaceHolderMain_SiteCollectionAdmin_RptControls_PolicyPolicies',
							'#ctl00_PlaceHolderMain_SiteAdministration_RptControls_PolicyPolicyAndLifecycle',
							'#ctl00_PlaceHolderMain_SiteCollectionAdmin_RptControls_HubUrlLinks',
							'#ctl00_PlaceHolderMain_SiteCollectionAdmin_RptControls_Portal',
							'#ctl00_PlaceHolderMain_SiteCollectionAdmin_RptControls_HtmlFieldSecurity'
							];
				$.each(links, function(i, sel) {
					$(sel).remove();
				});
			}
		}
	});

})();
