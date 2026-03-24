import Foundation

struct ChecklistData {
    static let allSections: [SurveySection] = [
        SurveySection(id: "details", title: "Kitchen Details", items: [
            SurveyItem(q: "Type of Kitchen (Jamaat / Faiz / Both)?", type: .text),
            SurveyItem(q: "Condition of Kitchen (Good / Needs Renovation / Requires Attention)?", type: .text),
            SurveyItem(q: "Kitchen Structure (Covered / Partly Covered / Open)?", type: .text),
            SurveyItem(q: "Proper space allotted for different operations?", type: .status)
        ]),
        SurveySection(id: "office", title: "Kitchen Office & Layout", items: [
            SurveyItem(q: "All activities can be monitored from here?", type: .status),
            SurveyItem(q: "Adequate natural light?", type: .status),
            SurveyItem(q: "Adequate electrical, LAN, and telephone connections?", type: .status),
            SurveyItem(q: "Monitoring system (i.e. CCTV)?", type: .status),
            SurveyItem(q: "Desk and chair?", type: .status),
            SurveyItem(q: "Computer and printer?", type: .status),
            SurveyItem(q: "Lockable key cupboard and filing cabinet?", type: .status),
            SurveyItem(q: "Notice board?", type: .status),
            SurveyItem(q: "Condition of Floors (Non-slippery / Sloped)?", type: .text),
            SurveyItem(q: "Appropriate Air flow/Ventilation type (Windows/Exhaust)?", type: .text),
            SurveyItem(q: "Structure & fittings of impermeable material?", type: .status),
            SurveyItem(q: "Wall Protection (Granite/PVC/Corner guards)?", type: .text),
            SurveyItem(q: "Concealed Electric Fixtures?", type: .status),
            SurveyItem(q: "Socket points at suitable height?", type: .status)
        ]),
        // ... (Full data would be here, including all sections from the JS file)
        SurveySection(id: "safety", title: "Safety, Fire & Utilities", items: [
            SurveyItem(q: "Is Operative Calendar followed?", type: .status),
            SurveyItem(q: "Gas Bank in designated area?", type: .status),
            SurveyItem(q: "Testing of potable water (NABL Labs)?", type: .text),
            SurveyItem(q: "RO Filter regular checking?", type: .status),
            SurveyItem(q: "Emergency devices (Extinguishers/Blankets)?", type: .text),
            SurveyItem(q: "Emergency Light Facility?", type: .status),
            SurveyItem(q: "Safety sign boards present?", type: .status),
            SurveyItem(q: "First Aid Box available?", type: .status),
            SurveyItem(q: "Fire exits available?", type: .status)
        ])
    ]
}
