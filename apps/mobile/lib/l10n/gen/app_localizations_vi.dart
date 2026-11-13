// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Vietnamese (`vi`).
class AppLocalizationsVi extends AppLocalizations {
  AppLocalizationsVi([String locale = 'vi']) : super(locale);

  @override
  String get appTitle => 'DevPulse';

  @override
  String get retry => 'Thử lại';

  @override
  String get tryAgain => 'Thử lại';

  @override
  String get cancel => 'Hủy';

  @override
  String get done => 'Xong';

  @override
  String get all => 'Tất cả';

  @override
  String get view => 'Xem';

  @override
  String get loading => 'Đang tải';

  @override
  String get loadingEllipsis => 'Đang tải…';

  @override
  String get couldNotLoad => 'Không tải được';

  @override
  String get couldNotLoadThis => 'Không tải được nội dung này';

  @override
  String get youreOffline => 'Bạn đang ngoại tuyến';

  @override
  String get unknown => 'Không rõ';

  @override
  String get you => 'Bạn';

  @override
  String get someone => 'Ai đó';

  @override
  String get demo => 'DEMO';

  @override
  String inProgressLabel(String label) {
    return '$label, đang xử lý';
  }

  @override
  String requestRef(String id) {
    return 'Mã tham chiếu: $id';
  }

  @override
  String pageNotFound(String path) {
    return 'Không tìm thấy trang: $path';
  }

  @override
  String get justNow => 'vừa xong';

  @override
  String minutesAgo(num n) {
    return '$n phút trước';
  }

  @override
  String hoursAgo(num n) {
    return '$n giờ trước';
  }

  @override
  String daysAgo(num n) {
    return '$n ngày trước';
  }

  @override
  String get healthHealthy => 'Bình thường';

  @override
  String get healthDegraded => 'Suy giảm';

  @override
  String get healthCritical => 'Nghiêm trọng';

  @override
  String get healthUnknown => 'Không rõ';

  @override
  String healthSemantics(String label) {
    return 'Tình trạng: $label';
  }

  @override
  String severitySemantics(num n) {
    return 'Mức độ $n';
  }

  @override
  String get statusTriggered => 'Đã kích hoạt';

  @override
  String get statusAcknowledged => 'Đã xác nhận';

  @override
  String get statusResolved => 'Đã giải quyết';

  @override
  String get roleOwner => 'Chủ sở hữu';

  @override
  String get roleAdmin => 'Quản trị viên';

  @override
  String get roleEngineer => 'Kỹ sư';

  @override
  String get roleViewer => 'Người xem';

  @override
  String get noDataInRange => 'Không có dữ liệu trong khoảng này';

  @override
  String get navOverview => 'Tổng quan';

  @override
  String get navServices => 'Dịch vụ';

  @override
  String get navIncidents => 'Sự cố';

  @override
  String get navCopilot => 'Copilot';

  @override
  String get navSettings => 'Cài đặt';

  @override
  String get offlineBanner => 'Ngoại tuyến · đang hiện dữ liệu lưu trên máy';

  @override
  String pendingChanges(num n) {
    String _temp0 = intl.Intl.pluralLogic(n, locale: localeName, other: '$n thay đổi đang chờ đồng bộ');
    return '$_temp0';
  }

  @override
  String changeNotApplied(String message) {
    return 'Không áp dụng được một thay đổi: $message';
  }

  @override
  String get signIn => 'Đăng nhập';

  @override
  String get createYourAccount => 'Tạo tài khoản của bạn';

  @override
  String get createAccount => 'Tạo tài khoản';

  @override
  String get name => 'Họ tên';

  @override
  String get workEmail => 'Email công việc';

  @override
  String get password => 'Mật khẩu';

  @override
  String get passwordHint => 'Ít nhất 12 ký tự.';

  @override
  String get passwordTooShort => 'Mật khẩu cần ít nhất 12 ký tự.';

  @override
  String get invalidEmail => 'Nhập địa chỉ email hợp lệ.';

  @override
  String get checkFields => 'Vui lòng kiểm tra các trường được đánh dấu.';

  @override
  String get goToRegister => 'Lần đầu dùng DevPulse? Tạo tài khoản';

  @override
  String get goToLogin => 'Đã có tài khoản? Đăng nhập';

  @override
  String get restoringSession => 'Đang khôi phục phiên đăng nhập';

  @override
  String get sessionEnded => 'Phiên đăng nhập đã kết thúc. Vui lòng đăng nhập lại.';

  @override
  String get errNetwork => 'Không kết nối được tới DevPulse. Hãy kiểm tra kết nối mạng.';

  @override
  String get errInsecure => 'Không thiết lập được kết nối bảo mật.';

  @override
  String get errSlow => 'Phản hồi mất quá nhiều thời gian để xử lý.';

  @override
  String get errCancelled => 'Yêu cầu đã bị hủy';

  @override
  String get errTooMany => 'Bạn đã thử quá nhiều lần. Vui lòng đợi vài phút rồi thử lại.';

  @override
  String get errServer => 'DevPulse đang gặp sự cố. Vui lòng thử lại sau ít phút.';

  @override
  String get errGeneric => 'Đã xảy ra lỗi. Vui lòng thử lại.';

  @override
  String get errInvalidCredentials => 'Email hoặc mật khẩu không đúng';

  @override
  String get errEmailTaken => 'Email này đã có tài khoản';

  @override
  String get errVersionMismatch => 'Người khác vừa thay đổi mục này. Hãy tải lại rồi thử lại.';

  @override
  String get errInvalidTransition => 'Không thể thực hiện thao tác này ở trạng thái hiện tại của sự cố.';

  @override
  String get errMaxEscalation => 'Sự cố đã ở cấp leo thang cao nhất.';

  @override
  String get errSlugTaken => 'Tên này đã được dùng. Hãy chọn tên khác.';

  @override
  String get organizations => 'Tổ chức';

  @override
  String get offlineOrgs => 'Bạn đang ngoại tuyến. Đang hiện danh sách tổ chức gần nhất.';

  @override
  String get yourOrganizations => 'Tổ chức của bạn';

  @override
  String get current => 'Hiện tại';

  @override
  String get createFirstOrg => 'Tạo tổ chức đầu tiên';

  @override
  String get createAnotherOrg => 'Tạo thêm tổ chức';

  @override
  String get orgIntro => 'Mỗi tổ chức có dịch vụ, sự cố và thành viên riêng.';

  @override
  String get orgName => 'Tên tổ chức';

  @override
  String get orgNameLength => 'Dùng từ 2 đến 120 ký tự.';

  @override
  String get createOrg => 'Tạo tổ chức';

  @override
  String get noServicesTitle => 'Chưa kết nối dịch vụ nào';

  @override
  String get noServicesBody =>
      'Tạo dịch vụ và khóa nhận dữ liệu trên trang web, rồi gửi dữ liệu giám sát. Tình trạng, độ trễ và sự cố sẽ hiện ở đây.';

  @override
  String criticalOpen(num n) {
    String _temp0 = intl.Intl.pluralLogic(n, locale: localeName, other: 'Đang có $n sự cố nghiêm trọng');
    return '$_temp0';
  }

  @override
  String get overviewStale => 'Ngoại tuyến · đang hiện bản tổng quan lưu trên máy';

  @override
  String get noTelemetryWindow => 'Không nhận được dữ liệu trong khoảng đã chọn — hãy thử khoảng dài hơn.';

  @override
  String get requests => 'Yêu cầu';

  @override
  String get errorRate => 'Tỷ lệ lỗi';

  @override
  String get avgLatency => 'Độ trễ TB';

  @override
  String get p95Latency => 'Độ trễ p95';

  @override
  String get approx => 'xấp xỉ';

  @override
  String get requestVolume => 'Lưu lượng yêu cầu';

  @override
  String requestVolumeSemantics(String count) {
    return 'Biểu đồ lưu lượng, $count yêu cầu trong khoảng này';
  }

  @override
  String get recentIncidents => 'Sự cố gần đây';

  @override
  String get noIncidents => 'Không có sự cố';

  @override
  String get allQuiet => 'Mọi thứ ổn định.';

  @override
  String get recentDeployments => 'Lượt triển khai gần đây';

  @override
  String get noDeploymentsYet => 'Chưa có lượt triển khai nào';

  @override
  String get sendFromCi => 'Gửi từ CI hoặc kết nối GitHub.';

  @override
  String servicesCount(num n) {
    String _temp0 = intl.Intl.pluralLogic(n, locale: localeName, other: 'dịch vụ');
    return '$_temp0';
  }

  @override
  String healthCountSemantics(num n, String label) {
    return '$n $label';
  }

  @override
  String get deployments => 'Lượt triển khai';

  @override
  String get deploymentsEmptyBody =>
      'Gửi sự kiện triển khai từ CI bằng khóa nhận dữ liệu, hoặc kết nối GitHub trên trang web.';

  @override
  String get searchServices => 'Tìm dịch vụ';

  @override
  String get noServicesYet => 'Chưa có dịch vụ nào';

  @override
  String get noMatchingServices => 'Không có dịch vụ phù hợp';

  @override
  String get servicesEmptyBody => 'Thêm dịch vụ và khóa nhận dữ liệu trên trang web, tình trạng sẽ hiện ở đây.';

  @override
  String get tryDifferentSearch => 'Hãy thử từ khóa khác hoặc bỏ bộ lọc.';

  @override
  String get noDataYet => 'chưa có dữ liệu';

  @override
  String get noDataYetCap => 'Chưa có dữ liệu';

  @override
  String seenAgo(String ago) {
    return 'thấy $ago';
  }

  @override
  String seenAgoCap(String ago) {
    return 'Thấy $ago';
  }

  @override
  String serviceMeta(String slug, String environment, String tier) {
    return '$slug · $environment · cấp $tier';
  }

  @override
  String get service => 'Dịch vụ';

  @override
  String get metricsError => 'Không tải được chỉ số';

  @override
  String get latencyP95 => 'Độ trễ p95';

  @override
  String get cpu => 'CPU';

  @override
  String chartSemantics(String title) {
    return 'Biểu đồ $title';
  }

  @override
  String get openIncidents => 'Sự cố đang mở';

  @override
  String get noOpenIncidents => 'Không có sự cố đang mở';

  @override
  String get noDeploymentsRecorded => 'Chưa ghi nhận lượt triển khai nào';

  @override
  String get tabOpen => 'Đang mở';

  @override
  String get mine => 'Của tôi';

  @override
  String get noOpenIncidentsAllClear => 'Không có sự cố đang mở — mọi thứ ổn định';

  @override
  String get noIncidentsMatch => 'Không có sự cố phù hợp';

  @override
  String get incidentsEmptyBody => 'Sự cố do quy tắc cảnh báo hoặc đội của bạn tạo sẽ hiện ở đây.';

  @override
  String get tryDifferentFilter => 'Hãy thử bộ lọc trạng thái hoặc mức độ khác.';

  @override
  String get loadOlderFailed => 'Không tải được — thử lại';

  @override
  String get loadOlder => 'Tải sự cố cũ hơn';

  @override
  String get waitingToSync => 'Đang chờ đồng bộ';

  @override
  String incidentTileSemantics(String severity, String key, String title, String status, String ago) {
    return '$severity $key, $title, $status, bắt đầu $ago';
  }

  @override
  String get incidentNotFound => 'Không tìm thấy sự cố';

  @override
  String get incidentNotFoundBody => 'Sự cố có thể thuộc tổ chức khác.';

  @override
  String get offlineSaved => 'Bạn đang ngoại tuyến. Thay đổi đã được lưu và sẽ tự động gửi đi.';

  @override
  String get resolveIncidentQ => 'Giải quyết sự cố?';

  @override
  String get resolutionNoteOptional => 'Ghi chú cách giải quyết (không bắt buộc)';

  @override
  String get resolve => 'Giải quyết';

  @override
  String get acknowledge => 'Xác nhận';

  @override
  String get assignToMe => 'Giao cho tôi';

  @override
  String get escalate => 'Leo thang';

  @override
  String get reopen => 'Mở lại';

  @override
  String escalatedTimes(num n) {
    return 'Đã leo thang ×$n';
  }

  @override
  String pendingAction(String action) {
    return 'Thao tác \"$action\" của bạn đang chờ gửi.';
  }

  @override
  String startedAgo(String ago) {
    return 'bắt đầu $ago';
  }

  @override
  String ownerName(String name) {
    return 'phụ trách: $name';
  }

  @override
  String resolution(String note) {
    return 'Cách giải quyết: $note';
  }

  @override
  String get timelineStale => 'Đang hiện dòng thời gian lưu trên máy.';

  @override
  String get relatedDeployments => 'Lượt triển khai có thể liên quan';

  @override
  String correlationSemantics(String pct, String kind) {
    return 'Tương quan $pct phần trăm, $kind';
  }

  @override
  String get timingOnly => 'Chỉ nghi ngờ dựa trên thời điểm — chưa phải nguyên nhân đã xác nhận.';

  @override
  String get timeline => 'Dòng thời gian';

  @override
  String get timelineError => 'Không tải được dòng thời gian';

  @override
  String get comments => 'Bình luận';

  @override
  String get noComments => 'Chưa có bình luận.';

  @override
  String get waitingToSend => 'đang chờ gửi';

  @override
  String get addComment => 'Thêm bình luận';

  @override
  String get sendComment => 'Gửi bình luận';

  @override
  String get correlationSuspected => 'nghi ngờ';

  @override
  String get correlationRuledOut => 'đã loại trừ';

  @override
  String get correlationConfirmed => 'đã xác nhận';

  @override
  String conflictNotApplied(String action) {
    return 'Thao tác \"$action\" chưa được áp dụng: người khác đã thay đổi sự cố này trước. Đang hiện bản mới nhất.';
  }

  @override
  String showingLatest(String message) {
    return '$message. Đang hiện bản mới nhất.';
  }

  @override
  String evOpenedByRule(String rule) {
    return 'Được mở bởi cảnh báo “$rule”';
  }

  @override
  String evOpenedBy(String who) {
    return 'Được mở bởi $who';
  }

  @override
  String evAcknowledged(String who) {
    return '$who đã xác nhận';
  }

  @override
  String evResolved(String who) {
    return '$who đã giải quyết';
  }

  @override
  String evResolvedNote(String who, String note) {
    return '$who đã giải quyết: $note';
  }

  @override
  String evReopened(String who) {
    return '$who đã mở lại';
  }

  @override
  String evAssigned(String who, String name) {
    return '$who đã giao cho $name';
  }

  @override
  String evUnassigned(String who) {
    return '$who đã bỏ người phụ trách';
  }

  @override
  String evEscalated(String who, String level) {
    return '$who đã leo thang lên cấp $level';
  }

  @override
  String evSeverityChanged(String who, String severity) {
    return '$who đã đổi mức độ thành $severity';
  }

  @override
  String evCommented(String who) {
    return '$who đã bình luận';
  }

  @override
  String evAlertAttached(String rule) {
    return 'Cảnh báo “$rule” lại kích hoạt';
  }

  @override
  String evAlertResolved(String rule) {
    return 'Cảnh báo “$rule” đã trở lại bình thường';
  }

  @override
  String evDeploymentCorrelated(String version) {
    return 'Lượt triển khai $version có thể liên quan';
  }

  @override
  String evProposalApproved(String who, String description) {
    return '$who đã duyệt bước do AI đề xuất “$description”';
  }

  @override
  String evProposalRejected(String who, String description) {
    return '$who đã từ chối bước do AI đề xuất “$description”';
  }

  @override
  String get evAiReady => 'Đã có phân tích AI';

  @override
  String get evAiUnavailable => 'Không có phân tích AI';

  @override
  String get evAiUpdated => 'Phân tích AI đã cập nhật';

  @override
  String get aiCopilot => 'AI Copilot';

  @override
  String get noInvestigations => 'Chưa có cuộc điều tra nào';

  @override
  String get noInvestigationsBody =>
      'Mở một sự cố và chạm \"Điều tra bằng AI\". Copilot thu thập chỉ số, log, lượt triển khai và đề xuất các nguyên nhân có thể kèm bằng chứng.';

  @override
  String get analysisReady => 'Đã có phân tích';

  @override
  String get triggerAuto => 'Tự động';

  @override
  String get triggerRequested => 'Theo yêu cầu';

  @override
  String get progressQueued => 'Đang chờ tiến trình xử lý…';

  @override
  String get progressCollecting => 'Đang thu thập chỉ số, log và lượt triển khai…';

  @override
  String get progressAnalyzing => 'Đang phân tích bằng chứng…';

  @override
  String get aiAnalysis => 'Phân tích AI';

  @override
  String get runAgain => 'Chạy lại';

  @override
  String get analysisStale => 'Đang hiện bản phân tích lưu trên máy.';

  @override
  String get aiLoadError => 'Không tải được phân tích AI';

  @override
  String get aiIntro =>
      'Copilot đọc chỉ số, log, lượt triển khai của sự cố này và các sự cố tương tự trước đây, rồi đề xuất các nguyên nhân có thể kèm bằng chứng cho từng nguyên nhân.';

  @override
  String get investigateWithAi => 'Điều tra bằng AI';

  @override
  String get investigateOffline => 'Điều tra (cần kết nối mạng)';

  @override
  String get analysisUnavailable => 'Không có phân tích';

  @override
  String get actionsUnaffected => 'Các thao tác với sự cố không bị ảnh hưởng.';

  @override
  String hypotheses(String ago) {
    return 'Giả thuyết — chưa được xác nhận · $ago';
  }

  @override
  String get probableCauses => 'Nguyên nhân có thể';

  @override
  String get nextSteps => 'Bước tiếp theo được đề xuất';

  @override
  String get couldNotSee => 'Những gì DevPulse không thấy được';

  @override
  String adjusted(String text) {
    return 'Đã điều chỉnh: $text';
  }

  @override
  String get askFollowUp => 'Hỏi thêm';

  @override
  String get helpful => 'Hữu ích';

  @override
  String get notHelpful => 'Không hữu ích';

  @override
  String get feedbackThanks => 'Cảm ơn, phản hồi của bạn giúp cải thiện điều tra viên AI.';

  @override
  String verify(String how) {
    return 'Cách kiểm chứng: $how';
  }

  @override
  String get approvedNotRun => '· Đã duyệt (DevPulse không tự thực hiện)';

  @override
  String get rejected => '· Đã từ chối';

  @override
  String get approve => 'Duyệt';

  @override
  String get reject => 'Từ chối';

  @override
  String get adminMustDecide => 'Quản trị viên phải quyết định với các thao tác có tính phá hủy.';

  @override
  String get approveQ => 'Duyệt thao tác này?';

  @override
  String approveBody(String description) {
    return '“$description”\n\nDuyệt sẽ ghi lại quyết định của bạn trên sự cố. DevPulse không tự chạy thao tác này: đội của bạn sẽ thực hiện.';
  }

  @override
  String get confidenceHigh => 'cao';

  @override
  String get confidenceMedium => 'trung bình';

  @override
  String get confidenceLow => 'thấp';

  @override
  String confidenceSemantics(String label, String pct) {
    return 'Độ tin cậy $label, $pct phần trăm';
  }

  @override
  String get riskReadOnly => 'Chỉ đọc';

  @override
  String get riskDestructive => 'Có tính phá hủy · cần quản trị viên duyệt';

  @override
  String get riskSensitive => 'Thay đổi hệ thống · cần phê duyệt';

  @override
  String get demoAnalyzer => 'BỘ PHÂN TÍCH DEMO · KHÔNG PHẢI LLM';

  @override
  String against(String ref) {
    return '$ref (phản bác)';
  }

  @override
  String evidenceComputed(String kind) {
    return 'Do DevPulse tính từ dữ liệu $kind đã lưu, không phải do AI.';
  }

  @override
  String evidenceSource(String source) {
    return 'Nguồn: $source';
  }

  @override
  String get askCopilot => 'Hỏi Copilot';

  @override
  String get askHint =>
      'Hỏi về sự cố này, vd. \"Lỗi bắt đầu từ khi nào?\" hoặc \"Đã từng gặp chưa?\". Câu trả lời đều dẫn bằng chứng; Copilot chỉ đọc dữ liệu, không bao giờ thay đổi gì.';

  @override
  String get lookingIntoIt => 'Đang tìm hiểu…';

  @override
  String get questionHint => 'Đặt câu hỏi thêm';

  @override
  String get needsConnection => 'Cần kết nối mạng';

  @override
  String get sendQuestion => 'Gửi câu hỏi';

  @override
  String lookedUp(String tool, String refs) {
    return 'Đã tra cứu $tool → $refs';
  }

  @override
  String get aiDisabled =>
      'Phân tích AI đang tắt cho tổ chức này. Quản trị viên có thể bật trong Cài đặt → AI trên trang web.';

  @override
  String get aiBudget => 'Ngân sách AI của tháng này đã hết. Quản trị viên có thể tăng trên trang web.';

  @override
  String get aiUnconfigured => 'Máy chủ DevPulse này chưa cấu hình nhà cung cấp AI nào.';

  @override
  String get aiNoEvidence => 'DevPulse không có dữ liệu giám sát cho sự cố này nên không có gì để phân tích.';

  @override
  String get aiInvalidOutput => 'Câu trả lời của AI không vượt qua bước kiểm tra nên đã bị loại bỏ.';

  @override
  String get aiRefused => 'Mô hình AI đã từ chối phân tích sự cố này.';

  @override
  String get aiTimeout => 'Quá trình phân tích mất quá nhiều thời gian.';

  @override
  String get aiUnavailable => 'Nhà cung cấp AI hiện không khả dụng. Vui lòng thử lại sau một phút.';

  @override
  String get aiStale => 'Quá trình phân tích đã bị gián đoạn.';

  @override
  String get aiAlreadyRunning => 'Đang có một phân tích chạy cho sự cố này.';

  @override
  String get aiFailed => 'Phân tích thất bại.';

  @override
  String get signOutQ => 'Đăng xuất?';

  @override
  String get signOutBody => 'Dữ liệu của tài khoản lưu trên thiết bị này sẽ bị xóa.';

  @override
  String get signOut => 'Đăng xuất';

  @override
  String get profile => 'Hồ sơ';

  @override
  String get organization => 'Tổ chức';

  @override
  String get noneSelected => 'Chưa chọn';

  @override
  String yourRole(String role) {
    return 'Vai trò của bạn: $role';
  }

  @override
  String get appearance => 'Giao diện';

  @override
  String get themeSystem => 'Hệ thống';

  @override
  String get themeDark => 'Tối';

  @override
  String get themeLight => 'Sáng';

  @override
  String get language => 'Ngôn ngữ';

  @override
  String get languageSystem => 'Theo máy';

  @override
  String get account => 'Tài khoản';

  @override
  String get settingsFooter => 'Tùy chọn thông báo và cài đặt bảo mật sẽ có khi bật thông báo đẩy (Giai đoạn 3).';
}
