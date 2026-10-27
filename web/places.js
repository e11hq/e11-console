// Countries (every ISO 3166 region, named by the browser in English) and main cities for the profile's
// "Your country" / "Your city" (other cities can be typed in).
window.E11_PLACES = (() => {
  const CODES = 'AF AX AL DZ AS AD AO AI AQ AG AR AM AW AU AT AZ BS BH BD BB BY BE BZ BJ BM BT BO BQ BA BW BV BR IO BN BG BF BI CV KH CM CA KY CF TD CL CN CX CC CO KM CG CD CK CR CI HR CU CW CY CZ DK DJ DM DO EC EG SV GQ ER EE SZ ET FK FO FJ FI FR GF PF TF GA GM GE DE GH GI GR GL GD GP GU GT GG GN GW GY HT HM VA HN HK HU IS IN ID IR IQ IE IM IL IT JM JP JE JO KZ KE KI KP KR KW KG LA LV LB LS LR LY LI LT LU MO MG MW MY MV ML MT MH MQ MR MU YT MX FM MD MC MN ME MS MA MZ MM NA NR NP NL NC NZ NI NE NG NU NF MK MP NO OM PK PW PS PA PG PY PE PH PN PL PT PR QA RE RO RU RW BL SH KN LC MF PM VC WS SM ST SA SN RS SC SL SG SX SK SI SB SO ZA GS SS ES LK SD SR SJ SE CH SY TW TJ TZ TH TL TG TK TO TT TN TR TM TC TV UG UA AE GB US UM UY UZ VU VE VN VG VI WF EH YE ZM ZW XK'.split(' ');
  let names = null;
  try { const dn = new Intl.DisplayNames(['en'], { type: 'region' }); names = (c) => { try { return dn.of(c) || c; } catch (e) { return c; } }; } catch (e) { names = (c) => c; }
  const COUNTRIES = CODES.map(names).filter((n, i, a) => n && a.indexOf(n) === i).sort((a, b) => a.localeCompare(b));
  const CITIES = {
    'United Arab Emirates': ['Abu Dhabi', 'Dubai', 'Sharjah', 'Ajman', 'Umm Al Quwain', 'Ras Al Khaimah', 'Fujairah', 'Al Ain'],
    Pakistan: ['Karachi', 'Lahore', 'Islamabad', 'Rawalpindi', 'Faisalabad', 'Multan', 'Peshawar', 'Quetta', 'Sialkot', 'Hyderabad'],
    India: ['Mumbai', 'Delhi', 'Bengaluru', 'Chennai', 'Hyderabad', 'Kolkata', 'Pune', 'Ahmedabad', 'Kochi', 'Thiruvananthapuram', 'Jaipur', 'Lucknow', 'Goa'],
    Syria: ['Damascus', 'Aleppo', 'Homs', 'Latakia', 'Hama', 'Tartus'],
    Lebanon: ['Beirut', 'Tripoli', 'Sidon', 'Tyre', 'Jounieh', 'Byblos', 'Zahle'],
    Armenia: ['Yerevan', 'Gyumri', 'Vanadzor', 'Vagharshapat'],
    Algeria: ['Algiers', 'Oran', 'Constantine', 'Annaba', 'Blida', 'Sétif'],
    'South Africa': ['Johannesburg', 'Cape Town', 'Durban', 'Pretoria', 'Port Elizabeth', 'Bloemfontein'],
    'Saudi Arabia': ['Riyadh', 'Jeddah', 'Mecca', 'Medina', 'Dammam', 'Khobar'],
    Qatar: ['Doha', 'Al Wakrah', 'Al Khor', 'Lusail'],
    Kuwait: ['Kuwait City', 'Hawalli', 'Salmiya', 'Ahmadi'],
    Bahrain: ['Manama', 'Muharraq', 'Riffa'],
    Oman: ['Muscat', 'Salalah', 'Sohar', 'Nizwa'],
    Egypt: ['Cairo', 'Alexandria', 'Giza', 'Sharm El Sheikh', 'Hurghada'],
    Jordan: ['Amman', 'Irbid', 'Zarqa', 'Aqaba'],
    Iraq: ['Baghdad', 'Erbil', 'Basra', 'Mosul', 'Sulaymaniyah'],
    Morocco: ['Casablanca', 'Rabat', 'Marrakesh', 'Tangier', 'Fes'],
    Tunisia: ['Tunis', 'Sfax', 'Sousse'],
    'United Kingdom': ['London', 'Manchester', 'Birmingham', 'Edinburgh', 'Glasgow', 'Liverpool', 'Leeds', 'Bristol'],
    'United States': ['New York', 'Los Angeles', 'Chicago', 'Houston', 'San Francisco', 'Miami', 'Seattle', 'Boston', 'Washington, D.C.'],
    Canada: ['Toronto', 'Vancouver', 'Montreal', 'Calgary', 'Ottawa'],
    Philippines: ['Manila', 'Quezon City', 'Cebu City', 'Davao City', 'Makati'],
    Bangladesh: ['Dhaka', 'Chittagong', 'Sylhet', 'Khulna'],
    'Sri Lanka': ['Colombo', 'Kandy', 'Galle'],
    Nepal: ['Kathmandu', 'Pokhara', 'Lalitpur'],
    Iran: ['Tehran', 'Mashhad', 'Isfahan', 'Shiraz', 'Tabriz'],
    Türkiye: ['Istanbul', 'Ankara', 'Izmir', 'Antalya', 'Bursa'],
    Turkey: ['Istanbul', 'Ankara', 'Izmir', 'Antalya', 'Bursa'],
    France: ['Paris', 'Lyon', 'Marseille', 'Nice', 'Toulouse'],
    Germany: ['Berlin', 'Munich', 'Hamburg', 'Frankfurt', 'Cologne'],
    Italy: ['Rome', 'Milan', 'Naples', 'Turin', 'Florence'],
    Spain: ['Madrid', 'Barcelona', 'Valencia', 'Seville', 'Málaga'],
    Russia: ['Moscow', 'Saint Petersburg', 'Kazan', 'Novosibirsk'],
    Ukraine: ['Kyiv', 'Kharkiv', 'Odesa', 'Lviv'],
    Nigeria: ['Lagos', 'Abuja', 'Kano', 'Port Harcourt'],
    Kenya: ['Nairobi', 'Mombasa', 'Kisumu'],
    Sudan: ['Khartoum', 'Omdurman', 'Port Sudan'],
    Yemen: ['Sanaa', 'Aden', 'Taiz'],
    Australia: ['Sydney', 'Melbourne', 'Brisbane', 'Perth', 'Adelaide'],
    China: ['Beijing', 'Shanghai', 'Guangzhou', 'Shenzhen', 'Hong Kong'],
    Indonesia: ['Jakarta', 'Surabaya', 'Bandung', 'Bali'],
    Malaysia: ['Kuala Lumpur', 'George Town', 'Johor Bahru'],
    Singapore: ['Singapore'],
  };
  const cities = (country) => CITIES[country] || [];
  // short forms on people's cards
  const SHORT = { 'United Arab Emirates': 'UAE', 'United Kingdom': 'UK', 'United States': 'USA', 'Saudi Arabia': 'KSA' };
  const short = (country) => SHORT[country] || country;
  return { COUNTRIES, cities, short };
})();
