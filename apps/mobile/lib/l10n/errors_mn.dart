/// Mongolian translations for backend error codes (the `detail` field of
/// error responses) and order statuses. Kept in one map, mirroring
/// apps/web/src/lib/messages.ts, so the two clients read as one product.
///
/// The web app's map only covers the codes its own screens can trigger;
/// this map adds the remaining codes the driver flows and shared
/// endpoints can return (see services/api/app/*.py `HTTPException` calls).
const Map<String, String> mnErrors = {
  'OTP_INVALID': 'Код буруу байна. Дахин шалгана уу.',
  'OTP_EXPIRED': 'Кодын хугацаа дууссан. Шинэ код авна уу.',
  'OTP_WAIT': 'Шинэ код авахын өмнө түр хүлээнэ үү.',
  'RATE_LIMITED': 'Хэт олон оролдлого хийлээ. Түр хүлээгээд дахин оролдоно уу.',
  'LOGIN_REQUIRED': 'Нэвтрэх хугацаа дууслаа.',
  'SESSION_EXPIRED': 'Нэвтрэх хугацаа дууслаа. Дахин нэвтэрнэ үү.',
  'ACTIVE_ORDER_EXISTS': 'Танд идэвхтэй захиалга байна.',
  'QUOTE_CHANGED': 'Үнэ шинэчлэгдсэн тул дахин тооцооллоо.',
  'CANCELLATION_UNAVAILABLE': 'Энэ захиалгыг одоо цуцлах боломжгүй.',
  'DRIVER_UNAVAILABLE': 'Жолооч одоогоор боломжгүй байна.',
  'PROVIDER_UNAVAILABLE': 'Гадаад үйлчилгээ түр ажиллахгүй байна.',
  'SERVICE_UNAVAILABLE': 'Үйлчилгээ түр ажиллахгүй байна.',
  'NETWORK': 'Интернэт холболтоо шалгаад дахин оролдоно уу.',
  'FORBIDDEN': 'Энэ үйлдлийг хийх эрхгүй байна.',
  'INVALID_INPUT': 'Оруулсан мэдээллээ шалгана уу.',
  'CONFLICT': 'Мэдээлэл зөрчилдлөө. Дахин оролдоно уу.',
  'IDEMPOTENCY_CONFLICT': 'Энэ захиалга өмнө нь илгээгдсэн байна.',
  'DRIVER_NOT_APPROVED': 'Таны жолоочийн бүртгэл зөвшөөрөгдөөгүй байна.',
  'DRIVER_ALREADY_REGISTERED': 'Та аль хэдийн жолоочоор бүртгүүлсэн байна.',
  'DRIVER_NOT_FOUND': 'Жолооч олдсонгүй.',
  'DRIVER_OFFLINE': 'Онлайн болсны дараа байршил илгээнэ үү.',
  'DRIVER_BUSY': 'Жолооч өөр захиалга гүйцэтгэж байна.',
  'ORDER_NOT_FOUND': 'Захиалга олдсонгүй.',
  'ORDER_ALREADY_ASSIGNED': 'Захиалгад жолооч аль хэдийн хуваарилагдсан байна.',
  'INVALID_STATUS_TRANSITION': 'Захиалгын төлөв шинэчлэгдсэн тул дахин шалгана уу.',
  'PAYMENT_REQUIRED': 'Захиалгыг дуусгахын өмнө төлбөрийг баталгаажуулна уу.',
  'PAYMENT_UNAVAILABLE': 'Энэ захиалгад төлбөр хийх боломжгүй байна.',
  'CASH_CONFIRMATION_UNAVAILABLE': 'Бэлэн мөнгийг одоо баталгаажуулах боломжгүй байна.',
  'REFUND_REQUIRES_DISPATCHER': 'Энэ захиалгыг цуцлахын тулд оператортой холбогдоно уу.',
  'REFUND_NOT_IMPLEMENTED': 'Төлбөр буцаах шаардлагатай тул оператортой холбогдоно уу.',
  'RATING_UNAVAILABLE': 'Энэ захиалгад одоо үнэлгээ өгөх боломжгүй байна.',
  'REASON_REQUIRED': 'Шалтгаанаа оруулна уу.',
  'TRACKING_EXPIRED': 'Энэ хяналтын холбоосын хугацаа дууссан байна.',
  'ROUTE_TOO_SHORT': 'Авах болон хүргэх хаяг хэт ойрхон байна.',
  'ROUTE_NOT_FOUND': 'Энэ хоёр хаягийн хоорондох замыг олдсонгүй.',
  'PLACE_NOT_FOUND': 'Хаяг олдсонгүй.',
  'SERVICE_NOT_FOUND': 'Үйлчилгээ олдсонгүй.',
  'VEHICLE_MISMATCH': 'Энэ жолоочийн машин уг үйлчилгээнд тохирохгүй байна.',
  'STAFF_REQUIRED': 'Энэ үйлдлийг зөвхөн ажилтан хийх боломжтой.',
  'ADMIN_REQUIRED': 'Энэ үйлдлийг зөвхөн админ хийх боломжтой.',
  'SMS_UNAVAILABLE': 'Код илгээх боломжгүй байна. Дахин оролдоно уу.',
  'INVALID_CALLBACK': 'Төлбөрийн мэдээлэл баталгаажсангүй.',
  'UNKNOWN': 'Алдаа гарлаа. Дахин оролдоно уу.',
};

const Map<String, String> mnStatuses = {
  'pending': 'Жолооч хайж байна',
  'assigned': 'Жолооч хуваарилсан',
  'driver_arriving': 'Жолооч замд гарсан',
  'arrived': 'Жолооч ирсэн',
  'picked_up': 'Ачаа авсан',
  'delivered': 'Хүргэсэн',
  'completed': 'Дууссан',
  'cancelled': 'Цуцлагдсан',
  'no_driver_found': 'Жолооч олдсонгүй',
};

String describeError(String code) => mnErrors[code] ?? mnErrors['UNKNOWN']!;

String describeStatus(String status) => mnStatuses[status] ?? status;
