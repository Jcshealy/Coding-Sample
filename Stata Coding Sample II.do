/*
    Corporate Board Demographics Dataset Construction
    
    This script constructs a panel dataset of corporate board composition from 
    BoardEx data, linking it to CRSP-Compustat identifiers. The analysis tracks 
    female representation on boards and committees over time, handles fiscal-to-
    calendar year alignment, and creates forward-looking indicators for analyzing
    board composition changes.
    
*/

clear
set more off
snapshot erase _all

global rootdir "T:\Users\TPC\CorporateBoards\Data"
global out_datapath "T:\Users\TPC\CorporateBoards\Data\Rebuild Testing Outputs"

* Clean BoardEx-CRSP-Compustat linking file
use "$rootdir\WRDS Linking\BoardEx CRSP Compustat\BoardEx_CRSP_Comp\skkgzumy6rinjezb", clear

	rename *, lower
	gen preferred_neg = preferred * -1
	sort companyid score preferred_neg gvkey permco 
	
	* Keep only best match per BoardEx company
	by companyid : gen dup = cond(_N==1, 0, _n)
	drop if dup > 1
	drop dup
	
	rename companyid boardex_id
	keep boardex_id gvkey permco
	
save "$out_datapath\Intermediate Cleans\CRSP-Compustat-BoardEx Link (Clean)", replace

* Clean individual director details
use "$rootdir\BoardEx\Individual Profile\individual details.dta\ex23183k7jn7qspy", clear

	keep dob dod gender directorid directorname
	gen female = (gender == "F")
	
	* Handle placeholder dates in raw data
	replace dod = . if dod == mdy(12,31,9999)
	replace dob = . if dob == mdy(01,01,1900)
	
	rename dob birthdate
	rename dod deathdate
	keep directorid female birthdate deathdate directorname
	compress

save "$out_datapath\Intermediate Cleans\BoardEx Individual Det (Clean)", replace

* Clean committee membership data
use "$rootdir\BoardEx\Committee Details\committee details.dta\yr9deortc4uetfac", clear

	rename boardid companyid

	* Identify audit committee membership and chairs
	gen committee_audit = (strpos(upper(committeename),"AUDIT") > 0)
	gen chair_audit = (committee_audit == 1 & strpos(upper(committeerolename),"CHAIR") > 0)
	replace chair_audit = 0 if committee_audit == 1 & strpos(upper(committeerolename),"VICE CHAIR") > 0

	* Identify nomination/governance committee
	gen committee_nomgov = (strpos(upper(committeename),"NOMINAT") > 0 | strpos(upper(committeename),"GOVERN") > 0)
	gen chair_nomgov = (committee_nomgov == 1 & strpos(upper(committeerolename),"CHAIR") > 0)
	replace chair_nomgov = 0 if committee_nomgov == 1 & strpos(upper(committeerolename),"VICE CHAIR") > 0

	* Identify compensation committee
	gen committee_comp = (strpos(upper(committeename),"COMPENSATION") > 0 | strpos(upper(committeename),"REMUNERATION") > 0)
	gen chair_comp = (committee_comp == 1 & strpos(upper(committeerolename),"CHAIR") > 0)
	replace chair_comp = 0 if committee_comp == 1 & strpos(upper(committeerolename),"VICE CHAIR") > 0

	* Consolidate multiple committee records per director-year
	sort companyid annualreportdate directorid
	local committees committee_audit chair_audit committee_nomgov chair_nomgov committee_comp chair_comp
	foreach var in `committees' {
		rename `var' temp
		by companyid annualreportdate directorid: egen `var' = max(temp)
		drop temp
	}

	keep companyid annualreportdate directorid `committees'
	rename (committee_audit committee_nomgov committee_comp) (comm_audit comm_nomgov comm_comp)
	duplicates drop companyid annualreportdate directorid, force
	compress
	
save "$out_datapath\Intermediate Cleans\Committee Det (Clean)", replace

* Merge datasets and construct panel
use "$rootdir\BoardEx\Organizational Summary\Analytics\organization analytics.dta\kqewljqo1xptg8ro", clear

	* Drop unused compensation and network variables
	cap drop stdev* eqlinkrem bonusratio totremperiod toteqatrisk estvaloptaward ///
	         intrvaloptaward ltipvalue valeqaward toteeqlinked estvalopt* intvalopt ///
	         valltipheld valtoteq penempcon other bonus salary remchgelast currency ///
	         rowtype ned directorname rolename timeretirement timeinco avgtimeothco ///
	         totnolstdbd totnoothlstdbd noquals totalcompensation wealthdelta ///
	         totaldirectcomp perftotal ticker isin hocountryname sector index ///
	         succession attrition nationality* totnounlstdbd totcurrnolstdbd timerole ///
	         totcurrnounlstdbd totcurrnoothlstdbd networksize
	
	rename timebrd time_on_board
	rename boardid companyid
	rename genderratio rep_genderratio
	rename numberdirectors rep_board_size
	
	* Create clean company-director-year panel
	gen year = year(annualreportdate)
	order companyid directorid year
	bys companyid directorid year : gen dup = cond(_N ==1, 0, _n)
	drop if dup > 1
	drop dup
	
	* Merge individual demographics
	sort directorid
	merge m:1 directorid using "$out_datapath\Intermediate Cleans\BoardEx Individual Det (Clean)"
	replace female = 0 if _merge == 1
	gen dir_noinfo = 1 if _merge == 1
	drop if _merge == 2
	drop _merge
	
	* Merge committee membership
	sort companyid directorid annualreportdate 
	merge m:1 companyid directorid annualreportdate using "$out_datapath\Intermediate Cleans\Committee Det (Clean)"
	keep if _merge == 1 | _merge == 3
	drop _merge
	
	* Fill missing committee indicators with zeros
	local committees comm_audit chair_audit comm_nomgov chair_nomgov comm_comp chair_comp
	foreach var in `committees' {
		replace `var' = 0 if `var' == .
	}

* Align fiscal year to calendar year
	sort companyid directorid year
	order companyid directorid year time_on_board
	
	gen cyear = .
	bysort companyid directorid : gen obs = _N
	gen report_before_630 = (annualreportdate < mdy(6, 30, year))
	
	* Assign first year of service (drop if less than 6 months)
	bysort companyid directorid (year): replace cyear = year if time_on_board > 0.5 & _n == 1 & report_before_630 == 0
	bysort companyid directorid (year): replace cyear = year - 1 if time_on_board > 0.5 & _n == 1 & report_before_630 == 1
	
	* Assign intermediate years based on reporting date
	bys companyid directorid (year): replace cyear = year if _n != _N & year[_n-1] == year - 1 & report_before_630 == 0
	bys companyid directorid (year): replace cyear = year - 1 if _n != _N & year[_n-1] == year - 1 & report_before_630 == 1
	
	* Assign last year of service (no death)
	bys companyid directorid (year): replace cyear = year if _n == _N & deathdate == . & report_before_630 == 0
	bys companyid directorid (year): replace cyear = year - 1 if _n == _N & deathdate == . & report_before_630 == 1
	
	* Handle deaths with less than 6 months remaining service
	bys companyid directorid (year): replace cyear = year - 1 if _n == _N & deathdate != . & ///
	    report_before_630 == 1 & inrange(deathdate - annualreportdate, 0, 182)
	bys companyid directorid (year): replace cyear = year if _n == _N & deathdate != . & ///
	    report_before_630 == 0 & inrange(deathdate - annualreportdate, 0, 182)
	
	* Expand observations for deaths with 6+ months service
	bys companyid directorid (year): gen temp = 1 if _n == _N & deathdate != . & ///
	    inrange(deathdate - annualreportdate, 183, 366)
	expand 2 if temp == 1, gen(expanded)
	
	replace cyear = year if report_before_630 == 0 & temp == 1 & expanded == 0
	replace cyear = year + 1 if report_before_630 == 0 & temp == 1 & expanded == 1
	replace cyear = year - 1 if report_before_630 == 1 & temp == 1 & expanded == 0
	replace cyear = year if report_before_630 == 1 & temp == 1 & expanded == 1
	drop temp expanded 
	
	drop year obs
	rename cyear year 
	drop if year == . 
	
	* Remove any remaining duplicates
	bys companyid directorid year: gen dup = cond(_N == 1, 0, _n)
	drop if dup > 1
	drop dup 

* Compute board composition variables at company-year level
	bys companyid year: gen board_size = _N
	bys companyid year: egen num_female = total(female)
	
	* Identify boards with any female directors
	bys companyid year: egen any_female = max(female)
	
	* Compute female representation on committees
	foreach comm in audit nomgov comp {
		bys companyid year: egen comm_size_`comm' = total(comm_`comm')
		
		gen temp = 1 if comm_`comm' == 1 & female == 1
		bys companyid year: egen comm_numf_`comm' = total(temp)
		drop temp
		
		bys companyid year: gen any_female_`comm' = (comm_numf_`comm' > 0)
		
		gen temp = (chair_`comm' == 1 & female == 1)
		bys companyid year: egen chair_`comm'_f = total(temp)
		drop temp
	}
	
	* Identify director deaths within a year of report date
	bys companyid directorid (year): gen temp = 1 if _n == _N & deathdate != . & ///
	    inrange(deathdate - annualreportdate, 0, 366)
	bys companyid directorid (year): gen tempf = 1 if _n == _N & deathdate != . & ///
	    inrange(deathdate - annualreportdate, 0, 366) & female == 1
	bys companyid directorid: gen tempm = 1 if _n == _N & deathdate != . & ///
	    inrange(deathdate - annualreportdate, 0, 366) & female == 0
	
	bysort companyid year: egen year_death = max(temp)
	bysort companyid year: egen year_deathm = max(tempm)
	bysort companyid year: egen year_deathf = max(tempf)
	drop temp tempf tempm
	
	foreach var in year_death year_deathm year_deathf {
		replace `var' = 0 if `var' == .
	}
	
	* Identify firms that ever experience director deaths
	bys companyid: egen any_death = max(year_death)
	bys companyid: egen any_deathm = max(year_deathm)
	bys companyid: egen any_deathf = max(year_deathf)
	
	* Collapse to company-year level
	bysort companyid year: keep if _n == 1
	drop female directorid annualreportdate time_on_board directorname deathdate birthdate ///
	     dir_noinfo boardname report_before_630
	
	rename companyid boardex_id
	
	* Compute female share and representation changes
	gen share_female = num_female / board_size
	sort boardex_id year
	by boardex_id: gen switch_0_some = (num_female[_n-1] == 0 & num_female[_n] > 0) & _n != 1
	by boardex_id: gen increase_female = (num_female[_n] > num_female[_n-1]) & _n != 1
	
	* Create forward-looking indicators for committee composition
	local fwd_vars chair_audit_f chair_nomgov_f chair_comp_f comm_numf_audit comm_numf_nomgov comm_numf_comp
	forval i = 1/3 {
		foreach var in `fwd_vars' {
			bys boardex_id: gen `var'_tp`i' = (`var'[_n+`i'] > 0 & year[_n+`i'] == year + `i')
		}
	}

* Link to CRSP-Compustat identifiers
	sort boardex_id 
	merge m:1 boardex_id using "$out_datapath\Intermediate Cleans\CRSP-Compustat-BoardEx Link (Clean)"
	keep if _merge == 3
	drop _merge
	
	* Drop intermediate committee indicators
	drop comm_audit comm_nomgov comm_comp chair_audit chair_nomgov chair_comp
	
	* Variable labels
	label var boardex_id "BoardEx Company ID"
	label var gvkey "CRSP-Compustat GVKEY"
	label var year "Calendar Year"
	label var board_size "Board Size (Computed)"
	label var num_female "Number of Female Directors"
	label var share_female "Female Share of Board"
	label var any_female "Indicator for Any Female Directors"
	label var year_death "Indicator for Director Death in Year"
	label var year_deathf "Indicator for Female Director Death in Year"
	label var comm_size_audit "Audit Committee Size"
	label var comm_numf_audit "Number of Women on Audit Committee"
	label var chair_audit_f "Female Audit Committee Chair"
	label var switch_0_some "Board Switched from Zero to Some Female Directors"
	label var increase_female "Number of Female Directors Increased from Prior Year"
	
	compress
	
	* Remove any remaining duplicates at gvkey-year level
	bysort gvkey year: gen dup = cond(_N == 1, 0, _n)
	drop if dup > 1
	drop dup
	
save "$out_datapath/boardex_built (new)", replace