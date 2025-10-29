/*
    Historical Building Tax Credit Analysis - Visualization Script
    
    This script generates eight visualizations analyzing qualified rehabilitation 
    expenses for historic buildings from 2001-2024. The analysis examines expense 
    distributions, geographic patterns, and trends over time by project type.

*/

clear all
set more off

cd "T:\\Users\\TPC\\Historical Tax Credit\\Empirical_work\\Data\\SavingPlaces\\2024 DTA"
use "national_list_2024_copy.dta", clear

* Data preparation: convert expense variable from string format to numeric
gen qualifiedexpenses_num = real(subinstr(subinstr(qualifiedexpenses, "$", "", .), ",", "", .))
drop qualifiedexpenses
rename qualifiedexpenses_num qualifiedexpenses

cap mkdir "outputs"
cap mkdir "outputs/graphs"

* Create log-transformed expense variable for distribution analysis
gen log_expenses = log10(qualifiedexpenses) if qualifiedexpenses > 0

* Graph 1: Expense distribution as percentage (log scale)

histogram log_expenses, bin(50) percent ///
    title("Distribution of Qualified Expenses") ///
    xtitle("Qualified Expenses") ///
    ytitle("Percent of Projects") ///
    xlabel(4 "$10K" 5 "$100K" 6 "$1M" 7 "$10M" 8 "$100M" 9 "$1B", labsize(small)) ///
    ylabel(0(2)12, format(%3.0f) labsize(small))
graph export "outputs/graphs/hist_log_percent.png", replace

* Graph 2: Expense distribution as count (log scale)

histogram log_expenses, bin(50) frequency ///
    title("Number of Projects by Expense Level") ///
    xtitle("Qualified Expenses") ///
    ytitle("Number of Projects") ///
    xlabel(4 "$10K" 5 "$100K" 6 "$1M" 7 "$10M" 8 "$100M" 9 "$1B", labsize(small)) ///
    ylabel(, format(%9.0fc) labsize(small))
graph export "outputs/graphs/hist_log_frequency.png", replace

* Graph 3: Project counts in established vs growing cities

preserve
keep city state qualifiedexpenses

* Create unique city identifier to handle cities with same names across states
gen city_state = city + ", " + state

* Classify selected cities into old vs new categories
gen city_type = ""
replace city_type = "Old" if city_state == "New York, NY"
replace city_type = "Old" if city_state == "Philadelphia, PA"
replace city_type = "Old" if city_state == "Boston, MA"
replace city_type = "Old" if city_state == "Chicago, IL"
replace city_type = "New" if city_state == "Austin, TX"
replace city_type = "New" if city_state == "Miami, FL"
replace city_type = "New" if city_state == "Seattle, WA"
replace city_type = "New" if city_state == "Las Vegas, NV"

keep if city_type != ""

collapse (count) n_projects=qualifiedexpenses, by(city_state city_type)

* Create separate variables for graph aesthetics
gen n_old = n_projects if city_type == "Old"
gen n_new = n_projects if city_type == "New"

* Sort to display old cities first, then new cities
gen sort_order = 1 if city_type == "Old"
replace sort_order = 2 if city_type == "New"
sort sort_order city_state

graph hbar n_old n_new, over(city_state, sort(sort_order) label(labsize(small))) ///
    bar(1, color(navy)) bar(2, color(orange)) ///
    title("Number of Projects: Old Cities vs New Cities") ///
    ytitle("Number of Projects") ///
    legend(order(1 "Old Cities" 2 "New Cities") size(small)) ///
    blabel(bar, format(%9.0fc) size(small))
graph export "outputs/graphs/bar_old_vs_new_cities.png", replace
restore

* Graph 4: Projects by census division

gen census_division = ""
replace census_division = "New England" if inlist(state, "CT", "ME", "MA", "NH", "RI", "VT")
replace census_division = "Mid Atlantic" if inlist(state, "NJ", "NY", "PA")
replace census_division = "E N Central" if inlist(state, "IL", "IN", "MI", "OH", "WI")
replace census_division = "W N Central" if inlist(state, "IA", "KS", "MN", "MO", "NE", "ND", "SD")
replace census_division = "S Atlantic" if inlist(state, "DE", "FL", "GA", "MD", "NC", "SC", "VA", "WV", "DC")
replace census_division = "E S Central" if inlist(state, "AL", "KY", "MS", "TN")
replace census_division = "W S Central" if inlist(state, "AR", "LA", "OK", "TX")
replace census_division = "Mountain" if inlist(state, "AZ", "CO", "ID", "MT", "NV", "NM", "UT", "WY")
replace census_division = "Pacific" if inlist(state, "AK", "CA", "HI", "OR", "WA")

preserve
collapse (count) n_projects=qualifiedexpenses, by(census_division)

graph hbar n_projects, over(census_division, sort(n_projects) descending label(labsize(small))) ///
    title("Projects by Census Division") ///
    ytitle("Number of Projects") ///
    blabel(bar, format(%9.0fc) size(small))
graph export "outputs/graphs/bar_census_division.png", replace
restore

* Graph 5: Stacked bar chart of project composition over time

preserve
keep fiscalyear projectuse qualifiedexpenses
* Standardize project use categories for analysis
replace projectuse = "Not_Reported" if projectuse == "Not Reported"
replace projectuse = "MultiUse" if projectuse == "Multi-Use"
collapse (sum) expenses=qualifiedexpenses, by(fiscalyear projectuse)
* Reshape to wide format for stacked bar chart
reshape wide expenses, i(fiscalyear) j(projectuse) string

graph bar expensesCommercial expensesHousing expensesHotel expensesMultiUse expensesOffice ///
    expensesOther expensesNot_Reported, over(fiscalyear, label(labsize(vsmall)) relabel(1 "2001" 2 " " 3 " " 4 "2004" 5 " " 6 " " 7 "2007" 8 " " 9 " " 10 "2010" 11 " " 12 " " 13 "2013" 14 " " 15 " " 16 "2016" 17 " " 18 " " 19 "2019" 20 " " 21 " " 22 "2022" 23 " " 24 " ")) stack ///
    title("Project Type Composition Over Time") ///
    ytitle("Total Qualified Expenses ($)", margin(medlarge)) ///
    ylabel(0 "0" 2e+09 "2B" 4e+09 "4B" 6e+09 "6B" 8e+09 "8B" 1e+10 "10B", labsize(small) angle(0)) ///
    legend(order(1 "Comm" 2 "Housing" 3 "Hotel" 4 "Multi-Use" ///
                 5 "Office" 6 "Other" 7 "Not Rpt") size(small) rows(2))
graph export "outputs/graphs/stacked_bar_type_by_year.png", replace
restore

* Graph 6: Number of projects by type over time

preserve
collapse (count) n_projects=qualifiedexpenses, by(fiscalyear projectuse)
tempfile by_type
save `by_type'
restore

preserve
collapse (count) total_n=qualifiedexpenses, by(fiscalyear)
tempfile total_count
save `total_count'
restore

use `by_type', clear
merge m:1 fiscalyear using `total_count', nogen

twoway ///
    (line n_projects fiscalyear if projectuse=="Housing", lwidth(medthick) lcolor(navy)) ///
    (line n_projects fiscalyear if projectuse=="Commercial", lwidth(medthick) lcolor(maroon)) ///
    (line n_projects fiscalyear if projectuse=="Hotel", lwidth(medium) lcolor(forest_green)) ///
    (line n_projects fiscalyear if projectuse=="Office", lwidth(medium) lcolor(orange)) ///
    (line n_projects fiscalyear if projectuse=="Multi-Use", lwidth(medium) lcolor(purple)) ///
    (line total_n fiscalyear, lwidth(thick) lcolor(black) lpattern(dash)), ///
    title("Number of Projects by Type Over Time") ///
    xtitle("Fiscal Year", margin(medium)) ///
    ytitle("Number of Projects", margin(medlarge)) ///
    ylabel(0 "0" 200 "200" 400 "400" 600 "600" 800 "800" 1000 "1K", labsize(small) angle(0)) ///
    xlabel(2001 2004 2007 2010 2013 2016 2019 2022, labsize(small)) ///
    legend(order(1 "Housing" 2 "Comm" 3 "Hotel" 4 "Office" 5 "Multi-Use" 6 "Total") ///
           size(small) rows(2))
graph export "outputs/graphs/line_count_by_type.png", replace

* Graph 7: Total qualified expenses by type over time

use "national_list_2024_copy.dta", clear
gen qualifiedexpenses_num = real(subinstr(subinstr(qualifiedexpenses, "$", "", .), ",", "", .))
drop qualifiedexpenses
rename qualifiedexpenses_num qualifiedexpenses

preserve
collapse (sum) total_exp=qualifiedexpenses, by(fiscalyear projectuse)
tempfile by_type_exp
save `by_type_exp'
restore

preserve
collapse (sum) total_all=qualifiedexpenses, by(fiscalyear)
tempfile total_exp
save `total_exp'
restore

use `by_type_exp', clear
merge m:1 fiscalyear using `total_exp', nogen

twoway ///
    (line total_exp fiscalyear if projectuse=="Housing", lwidth(medthick) lcolor(navy)) ///
    (line total_exp fiscalyear if projectuse=="Commercial", lwidth(medthick) lcolor(maroon)) ///
    (line total_exp fiscalyear if projectuse=="Hotel", lwidth(medium) lcolor(forest_green)) ///
    (line total_exp fiscalyear if projectuse=="Office", lwidth(medium) lcolor(orange)) ///
    (line total_exp fiscalyear if projectuse=="Multi-Use", lwidth(medium) lcolor(purple)) ///
    (line total_all fiscalyear, lwidth(thick) lcolor(black) lpattern(dash)), ///
    title("Total Qualified Expenses by Type Over Time") ///
    xtitle("Fiscal Year", margin(medium)) ///
    ytitle("Total Expenses ($)", margin(medlarge)) ///
    ylabel(0 "0" 2e+09 "2B" 4e+09 "4B" 6e+09 "6B" 8e+09 "8B", labsize(small) angle(0)) ///
    xlabel(2001 2004 2007 2010 2013 2016 2019 2022, labsize(small)) ///
    legend(order(1 "Housing" 2 "Comm" 3 "Hotel" 4 "Office" 5 "Multi-Use" 6 "Total") ///
           size(small) rows(2))
graph export "outputs/graphs/line_total_expenses_by_type.png", replace

* Graph 8: Average expenses per project by type over time

use "national_list_2024_copy.dta", clear
gen qualifiedexpenses_num = real(subinstr(subinstr(qualifiedexpenses, "$", "", .), ",", "", .))
drop qualifiedexpenses
rename qualifiedexpenses_num qualifiedexpenses

preserve
collapse (mean) avg_exp=qualifiedexpenses, by(fiscalyear projectuse)
tempfile by_type_avg
save `by_type_avg'
restore

preserve
collapse (mean) avg_all=qualifiedexpenses, by(fiscalyear)
tempfile total_avg
save `total_avg'
restore

use `by_type_avg', clear
merge m:1 fiscalyear using `total_avg', nogen

twoway ///
    (line avg_exp fiscalyear if projectuse=="Housing", lwidth(medthick) lcolor(navy)) ///
    (line avg_exp fiscalyear if projectuse=="Commercial", lwidth(medthick) lcolor(maroon)) ///
    (line avg_exp fiscalyear if projectuse=="Hotel", lwidth(medium) lcolor(forest_green)) ///
    (line avg_exp fiscalyear if projectuse=="Office", lwidth(medium) lcolor(orange)) ///
    (line avg_exp fiscalyear if projectuse=="Multi-Use", lwidth(medium) lcolor(purple)) ///
    (line avg_all fiscalyear, lwidth(thick) lcolor(black) lpattern(dash)), ///
    title("Average Qualified Expenses by Type Over Time") ///
    xtitle("Fiscal Year", margin(medium)) ///
    ytitle("Average Expenses ($)", margin(medlarge)) ///
    ylabel(0 "0" 1e+07 "10M" 2e+07 "20M" 3e+07 "30M" 4e+07 "40M" 5e+07 "50M", labsize(small) angle(0)) ///
    xlabel(2001 2004 2007 2010 2013 2016 2019 2022, labsize(small)) ///
    legend(order(1 "Housing" 2 "Comm" 3 "Hotel" 4 "Office" 5 "Multi-Use" 6 "Total") ///
           size(small) rows(2))
graph export "outputs/graphs/line_avg_expenses_by_type.png", replace

di "Analysis complete! 9 graphs saved to outputs/graphs/"