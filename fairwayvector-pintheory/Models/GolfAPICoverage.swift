import Foundation

struct GolfAPICoverageRegion: Identifiable, Hashable {
    let name: String
    let countries: [String]

    var id: String { name }
}

enum GolfAPICoverage {
    static let regions: [GolfAPICoverageRegion] = [
        GolfAPICoverageRegion(name: "North America", countries: [
            "USA", "Canada", "Mexico", "Dominican Republic", "Puerto Rico", "Jamaica", "Bermuda", "Bahamas",
            "Trinidad and Tobago", "Panama", "Guatemala", "Barbados", "Costa Rica", "Haiti", "El Salvador", "Aruba",
            "Cayman Islands", "Cuba", "St.Vincent & Grenadines", "Honduras", "Saint Lucia", "Saint Kitts and Nevis",
            "Nicaragua", "Belize"
        ]),
        GolfAPICoverageRegion(name: "USA + Canada", countries: ["USA", "Canada"]),
        GolfAPICoverageRegion(name: "Europe", countries: [
            "UK", "Germany", "France", "Sweden", "Spain", "Italy", "Netherlands", "Ireland", "Denmark", "Austria",
            "Finland", "Czech Republic", "Norway", "Belgium", "Switzerland", "Portugal", "Iceland", "Poland", "Slovakia",
            "Türkiye", "Hungary", "Slovenia", "Estonia", "Cyprus", "Latvia", "Croatia", "Jersey", "Greece", "Romania",
            "Bulgaria", "Lithuania", "Luxembourg", "Guernsey", "Belarus", "Georgia", "Serbia", "Faroe Islands", "Albania",
            "Andorra", "Malta"
        ]),
        GolfAPICoverageRegion(name: "Asia", countries: [
            "South Korea", "Japan", "Thailand", "China", "Malaysia", "India", "Indonesia", "Vietnam", "Taiwan", "Philippines",
            "Pakistan", "Singapore", "United Arab Emirates", "Myanmar", "Hong Kong", "Ukraine", "Russia", "Saudi Arabia",
            "Cambodia", "Laos", "Qatar", "Sri Lanka", "Brunei", "Oman", "Bangladesh", "Afghanistan", "Kuwait", "Bhutan",
            "Papua New Guinea", "Kazakhstan", "Bahrain", "Azerbaijan", "Israel", "Anguilla", "Jordan", "Macau", "Samoa",
            "Uzbekistan", "Iran", "Lebanon", "Maldives"
        ]),
        GolfAPICoverageRegion(name: "Australia/Oceania", countries: [
            "Australia", "New Zealand", "Guam", "Fiji", "Virgin Islands", "New Caledonia", "Guadeloupe", "Solomon Islands"
        ]),
        GolfAPICoverageRegion(name: "Latin America and the Caribbean", countries: [
            "Argentina", "Mexico", "Brazil", "Chile", "Colombia", "Dominican Republic", "Puerto Rico", "Jamaica", "Venezuela",
            "Bermuda", "Ecuador", "Bahamas", "Trinidad and Tobago", "Uruguay", "Panama", "Guatemala", "Peru", "Paraguay",
            "Costa Rica", "Barbados", "Haiti", "El Salvador", "French Polynesia", "Aruba", "Bolivia", "Cayman Islands", "Cuba",
            "St.Vincent & Grenadines", "Honduras", "Saint Lucia", "Equatorial Guinea", "Guyana", "Saint Kitts and Nevis",
            "Nicaragua", "Belize"
        ]),
        GolfAPICoverageRegion(name: "Africa", countries: [
            "South Africa", "Morocco", "Nigeria", "Kenya", "Egypt", "Uganda", "Zimbabwe", "Mauritius", "Tunisia", "Ghana",
            "Zambia", "Swaziland", "Namibia", "Botswana", "Tanzania", "Malawi", "Congo, Democratic Republic", "Mozambique",
            "Rwanda", "Cameroon", "Cote d'Ivoire", "Seychelles", "Madagascar", "Angola", "Vanuatu", "Cap Verde", "Ethiopia",
            "Senegal", "Suriname", "Sierra Leone", "Algeria", "Congo, Republic", "Chad", "Burundi", "Benin", "Togo"
        ])
    ]
}
