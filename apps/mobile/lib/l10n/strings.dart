/// All user-facing Mongolian copy in one place (mirrors the intent of
/// apps/web/src/lib/messages.ts — "Keep UI strings in one place per app",
/// AGENTS.md section 12). Shared login/ordering copy matches the web
/// app's wording; the driver-only screens are new but follow the same
/// short, direct tone.
class Strings {
  const Strings._();

  static const brandTagline = 'Ачаагаа хэдхэн товшилтоор тээвэрлүүл';

  // Phone login
  static const phoneHeading = 'Утасны дугаараа оруулна уу';
  static const phoneSubtitle = 'Бид таны дугаарт 4 оронтой баталгаажуулах код илгээнэ.';
  static const phoneHint = '8888 8888';
  static const phoneContinue = 'Үргэлжлүүлэх';
  static const termsPrefix = 'Үргэлжлүүлснээр та ';
  static const termsLink = 'үйлчилгээний нөхцөл';
  static const termsSuffix = '-ийг зөвшөөрнө.';

  // OTP
  static const otpHeading = 'Кодоо оруулна уу';
  static String otpSubtitle(String phone) => '+976 $phone дугаарт илгээсэн 4 оронтой кодыг оруулна уу.';
  static const otpVerify = 'Баталгаажуулах';
  static const otpResend = 'Код дахин илгээх';
  static String otpResendCountdown(int seconds) => 'Дахин илгээх · $seconds сек';
  static const otpDevHint = 'Хөгжүүлэлтийн горимд баталгаажуулах код: 0000';

  // Customer home
  static String greeting(String? name) => name == null || name.isEmpty ? 'Сайн байна уу' : 'Сайн байна уу, $name';
  static const homeHeading = 'Юу ачуулах вэ?';
  static const searchPrompt = 'Хаашаа ачих вэ?';
  static const startingPricePrefix = 'Эхлэх үнэ ';
  static const menuCurrentOrder = 'Идэвхтэй захиалга';
  static const menuBecomeDriver = 'Жолооч болох';
  static const menuTrackByLink = 'Захиалгын явц хянах';
  static const menuLogout = 'Гарах';
  static const menuProfile = 'Профайл';

  // Route / quote screen
  static const currentLocation = 'Одоогийн байршил';
  static const dropoffHint = 'Хүргэх хаяг';
  static const chooseVehicle = 'Машинаа сонго';
  static const addLoader = 'Ачигч нэмэх';
  static const payQpay = 'QPay';
  static const payCash = 'Бэлэн мөнгө';
  static const dropoffRequiredHint = 'Захиалахын тулд хүргэх хаягаа оруулна уу.';
  static String orderButton(String serviceName, String priceText) => '$serviceName захиалах · $priceText';

  // Finding / tracking
  static const findingHeading = 'Жолооч хайж байна…';
  static String findingSubtitle(String serviceName) => 'Ойролцоох $serviceName жолооч нарт захиалгыг илгээлээ.';
  static const arrivalPrefix = 'Жолооч ирэх хүртэл';
  static const callDriver = 'Залгах';
  static const messageDriver = 'Мессеж';
  static const callUnavailable = 'Дуудлага хийх боломжгүй байна.';
  static const messageUnavailable = 'Мессеж илгээх боломжгүй байна.';
  static const linkOpenFailed = 'Холбоосыг нээж чадсангүй.';
  static const cancelOrder = 'Захиалга цуцлах';
  static const cancelConfirmTitle = 'Захиалгаа цуцлах уу?';
  static const cancelConfirmBody = 'Энэ үйлдлийг буцаах боломжгүй.';
  static const confirmYes = 'Тийм, цуцлах';
  static const confirmNo = 'Үгүй';
  static const cancelReasonDefault = 'Хэрэглэгч цуцалсан';
  static const payWithQpayButton = 'QPay төлбөр төлөх';
  static const qpayDemoNotice = 'Туршилтын горимд бодит төлбөр хийгдэхгүй.';
  static const qpayOpenLink = 'QPay нээх';
  static const orderFoundNoDriver = 'Ойролцоо жолооч олдсонгүй. Дахин оролдоно уу.';

  // Completion / rating
  static const deliveredHeading = 'Ачаа хүргэгдлээ';
  static const deliveredSubtitle = 'Манай үйлчилгээг сонгосонд баярлалаа.';
  static const rateDriverPrompt = 'Жолоочийн үйлчилгээг үнэлнэ үү';
  static const newOrder = 'Шинэ захиалга';
  static const thanksForRating = 'Үнэлгээ өгсөнд баярлалаа';

  // Public tracking
  static const publicTrackingHeading = 'Захиалгын явц хянах';
  static const publicTrackingHint = 'Захиалгын хяналтын холбоос эсвэл кодоо оруулна уу';
  static const publicTrackingOpen = 'Харах';
  static const publicTrackingInvalid = 'Холбоос идэвхгүй байна.';
  static const publicTrackingPrivacyNote = 'Энэхүү холбоос нь утасны дугаар болон төлбөрийн мэдээлэл харуулахгүй.';
  static const pickupLabel = 'Авах';
  static const dropoffLabel = 'Хүргэх';

  // Driver registration
  static const driverRegisterHeading = 'Жолоочоор бүртгүүлэх';
  static const driverRegisterSubtitle = 'Мэдээллээ бүрэн бөглөнө үү. Ажилтан баталгаажуулсны дараа захиалга хүлээн авах боломжтой болно.';
  static const driverNameLabel = 'Нэр';
  static const driverLicenseLabel = 'Жолооны үнэмлэхний мэдээлэл';
  static const driverServiceLabel = 'Үйлчилгээний төрөл';
  static const driverPlateLabel = 'Улсын дугаар';
  static const driverModelLabel = 'Машины загвар';
  static const driverCapacityLabel = 'Даацын багтаамж (кг)';
  static const driverRegisterSubmit = 'Бүртгүүлэх';
  static const driverPendingHeading = 'Бүртгэлийг шалгаж байна';
  static const driverPendingBody = 'Таны мэдээллийг ажилтан шалгаж байна. Зөвшөөрөгдсөний дараа онлайн болох боломжтой.';
  static const driverSuspendedHeading = 'Жолоочийн эрх түдгэлзүүлэгдсэн';
  static const driverSuspendedBody = 'Дэлгэрэнгүй мэдээллийг оператортой холбогдоно уу.';

  // Driver home
  static const driverOnline = 'Онлайн';
  static const driverOffline = 'Оффлайн';
  static const driverGoOnline = 'Онлайн болох';
  static const driverGoOffline = 'Оффлайн болох';
  static const driverNoOrder = 'Одоогоор оноогдсон захиалга алга';
  static const driverWaitingForOrder = 'Онлайн байна. Захиалга хүлээж байна…';
  static const driverOfflinePrompt = 'Захиалга хүлээн авахын тулд онлайн болно уу.';
  static const driverRatingLabel = 'Үнэлгээ';
  static const driverLocationPermissionNeeded = 'Онлайн болохын тулд байршил хандах эрх шаардлагатай.';

  // Driver order actions
  static const driverAccept = 'Хүлээж авах';
  static const driverArrived = 'Ирлээ';
  static const driverPickedUp = 'Ачаа авлаа';
  static const driverDelivered = 'Хүргэлээ';
  static const driverConfirmCash = 'Бэлэн мөнгө хүлээн авлаа';
  static const driverWaitingForQpay = 'Харилцагчийн QPay төлбөрийг хүлээж байна';
  static const driverCheckPayment = 'Төлбөр шалгах';
  static const driverOrderCompleted = 'Захиалга дууслаа';
  static const driverCustomerLabel = 'Харилцагч';
  static const driverCallCustomer = 'Харилцагчид залгах';

  // Generic states
  static const loading = 'Уншиж байна…';
  static const retry = 'Дахин оролдох';
  static const offlineTitle = 'Холболт тасарсан';
  static const offlineBody = 'Интернэт холболтоо шалгаад дахин оролдоно уу.';
  static const emptyServicesTitle = 'Үйлчилгээ ачаалагдсангүй';
  static const back = 'Буцах';
  static const close = 'Хаах';
  static const logoutConfirmTitle = 'Гарах уу?';
}
