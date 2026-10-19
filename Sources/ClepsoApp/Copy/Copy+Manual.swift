import Domain

extension Copy {
    enum Manual {
        static let title = "Other agents, by hand"
        static let subtitle = "Dated readings you enter yourself. These stay separate from automatic readings and do not trigger automatic alerts."
        static let add = "Add a reading…", update = "Update…", remove = "Remove…", cancel = "Cancel", save = "Save reading"
        static let entered = "Entered by you", stale = "Old reading", resetPassed = "Reset expected · check the provider again"
        static let notReported = "Not entered", selected = "Selected · not verified"
        static let empty = "Copy a percentage or reported reset time from an agent's own usage screen. No sign-in, credentials or page contents are collected."
        static let provider = "Agent", window = "Allowance window", used = "Used percent (optional)", measured = "When you checked"
        static let plan = "Plan", unknown = "Not sure", hasReset = "I have a reported reset time", reset = "Reported reset"
        static let overage = "I enabled paid usage beyond this allowance"
        static let overageNote = "Allowance exhausted · paid usage may continue (you confirmed this)"
        static let error = "Enter a percentage from 0 to 100 or a reported reset after the time you checked. Readings cannot be dated in the future."
        static let failed = "The reading could not be saved. Your earlier readings are unchanged."
        static let deleteTitle = "Remove this manually tracked allowance?"
        static let deleteBody = "This removes its current reading and earlier manual entries. Automatic agent readings are kept."
        static let open = "Open provider"
        static func scope(_ window: ManualAllowance.Window) -> String {
            switch window { case .fiveHour: "5-hour"; case .weekly: "Weekly"; case .daily: "Daily" }
        }
    }
}
