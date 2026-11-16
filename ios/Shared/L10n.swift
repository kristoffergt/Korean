import Foundation

/// The app's and the widgets' own words, in the page's three languages. The
/// page's language decides (it is sent over the bridge and stored with the
/// widgets' data); before the page has said, the phone's own.
enum L10n {
    static let languages = ["en", "ko", "vi"]

    static func lang(_ code: String?) -> String {
        if let code = code?.lowercased(), languages.contains(code) { return code }
        let phone = Locale.preferredLanguages.first.map { String($0.prefix(2)).lowercased() } ?? "en"
        return languages.contains(phone) ? phone : "en"
    }

    static func locale(_ lang: String) -> Locale {
        switch lang {
        case "ko": return Locale(identifier: "ko_KR")
        case "vi": return Locale(identifier: "vi_VN")
        default: return Locale(identifier: "en_US")
        }
    }

    static func t(_ key: String, _ lang: String) -> String {
        guard let row = table[key] else { return key }
        switch lang {
        case "ko": return row.1
        case "vi": return row.2
        default: return row.0
        }
    }

    /// A word with a number in it: `key` is the plural ("{n} days left"),
    /// `key + "One"` the singular, used for exactly 1. Only English inflects;
    /// Korean and Vietnamese have one form, the same text in both entries.
    static func count(_ key: String, _ n: Int, _ lang: String) -> String {
        let form = n == 1 && table[key + "One"] != nil ? key + "One" : key
        return t(form, lang).replacingOccurrences(of: "{n}", with: String(n))
    }

    private static let table: [String: (String, String, String)] = [
        // Alerts from the page.
        "ok": ("OK", "확인", "OK"),
        "cancel": ("Cancel", "취소", "Hủy"),
        // No connection on the first load.
        "offlineTitle": ("You're offline", "인터넷에 연결되어 있지 않아요", "Bạn đang ngoại tuyến"),
        "offlineBody": ("Check your connection and try again.", "연결을 확인한 뒤 다시 시도해 주세요.", "Hãy kiểm tra kết nối rồi thử lại."),
        "retry": ("Try again", "다시 시도", "Thử lại"),
        // The Face ID lock.
        "lockTitle": ("Locked", "잠겨 있어요", "Đã khóa"),
        "unlock": ("Unlock", "잠금 해제", "Mở khóa"),
        "lockReason": ("Unlock your tracker", "트래커의 잠금을 해제합니다", "Mở khóa ứng dụng"),
        // Holding a link to another site.
        "open": ("Open", "열기", "Mở"),
        "openInSafari": ("Open in Safari", "Safari에서 열기", "Mở trong Safari"),
        "copyLink": ("Copy link", "링크 복사", "Sao chép liên kết"),
        "share": ("Share", "공유", "Chia sẻ"),

        // Widgets: names in the widget gallery.
        "wUpNextName": ("Up next", "다가오는 일", "Việc sắp tới"),
        "wUpNextDesc": ("This month and what is coming up.", "이번 달과 다가오는 일.", "Tháng này và những việc sắp tới."),
        "wWeekName": ("Week", "이번 주", "Tuần"),
        "wWeekDesc": ("Your week, day by day.", "이번 주를 하루씩.", "Tuần của bạn, từng ngày."),
        "wDayName": ("Day", "하루", "Ngày"),
        "wDayDesc": ("Today's events and to-dos in order.", "오늘의 일정과 할 일을 순서대로.", "Sự kiện và việc cần làm hôm nay theo thứ tự."),
        "wMonthName": ("Five weeks", "5주", "Năm tuần"),
        "wMonthDesc": ("Last week and the four after it.", "지난주와 그 뒤 4주.", "Tuần trước và bốn tuần sau đó."),
        "wTodoName": ("To-dos", "할 일", "Việc cần làm"),
        "wTodoDesc": ("One of your to-do lists.", "할 일 목록 하나.", "Một danh sách việc cần làm."),
        "wYearName": ("Year", "올해", "Năm"),
        "wYearDesc": ("How much of the year has gone.", "올해가 얼마나 지났는지.", "Một năm đã trôi qua bao nhiêu."),
        "wStudyName": ("Today", "오늘", "Hôm nay"),
        "wStudyDesc": ("Study time and what is left to do today.", "오늘 공부한 시간과 남은 할 일.", "Thời gian học và việc còn lại hôm nay."),

        // Widgets: the to-do lists.
        "listToday": ("Today", "오늘", "Hôm nay"),
        "listWeek": ("This week", "이번 주", "Tuần này"),
        "listMonth": ("This month", "이번 달", "Tháng này"),
        "listYear": ("This year", "올해", "Năm nay"),
        "listUpcoming": ("Upcoming", "다가오는 일", "Sắp tới"),

        // Widgets: words inside them.
        "upcoming": ("Up next", "다가오는 일", "Việc sắp tới"),
        "allDay": ("all day", "종일", "cả ngày"),
        "allDayLong": ("All day", "종일", "Cả ngày"),
        "today": ("Today", "오늘", "Hôm nay"),
        "tomorrow": ("Tomorrow", "내일", "Ngày mai"),
        // "+3 more": no noun after the number, so no singular form.
        "more": ("+{n} more", "+{n}개 더", "+{n} việc nữa"),
        "nothingNext": ("Nothing coming up", "다가오는 일이 없어요", "Không có việc sắp tới"),
        "nothingToday": ("Nothing planned today", "오늘은 일정이 없어요", "Hôm nay không có kế hoạch"),
        "listEmpty": ("Nothing here", "할 일이 없어요", "Không có việc nào"),
        "allDone": ("All done", "모두 완료", "Xong hết rồi"),
        "todosLeft": ("{n} to-dos left", "할 일 {n}개 남음", "Còn {n} việc"),
        "todosLeftOne": ("{n} to-do left", "할 일 {n}개 남음", "Còn {n} việc"),
        "studied": ("Studied today", "오늘 공부", "Đã học hôm nay"),
        "goalOf": ("of {g}", "목표 {g}", "trên {g}"),
        "yearGone": ("{p}% of the year has gone", "올해의 {p}%가 지났어요", "{p}% năm đã trôi qua"),
        "daysLeft": ("{n} days left", "{n}일 남음", "còn {n} ngày"),
        "daysLeftOne": ("{n} day left", "{n}일 남음", "còn {n} ngày"),
        "openApp": ("Open the app to load your day", "앱을 열어 오늘을 불러오세요", "Mở ứng dụng để tải dữ liệu hôm nay"),
        "signIn": ("Sign in in the app", "앱에서 로그인하세요", "Đăng nhập trong ứng dụng"),
        "chooseList": ("List", "목록", "Danh sách"),
    ]
}
