export const mn = {
  errors: {
    OTP_INVALID:'Код буруу байна. Дахин шалгана уу.', OTP_EXPIRED:'Кодын хугацаа дууссан. Шинэ код авна уу.',
    OTP_WAIT:'Шинэ код авахын өмнө түр хүлээнэ үү.', RATE_LIMITED:'Хэт олон оролдлого хийлээ. Түр хүлээгээд дахин оролдоно уу.',
    LOGIN_REQUIRED:'Нэвтрэх хугацаа дууслаа.', ACTIVE_ORDER_EXISTS:'Танд идэвхтэй захиалга байна.',
    QUOTE_CHANGED:'Үнэ шинэчлэгдсэн тул дахин тооцооллоо.', CANCELLATION_UNAVAILABLE:'Энэ захиалгыг одоо цуцлах боломжгүй.',
    DRIVER_UNAVAILABLE:'Жолооч одоогоор боломжгүй байна.', PROVIDER_UNAVAILABLE:'Гадаад үйлчилгээ түр ажиллахгүй байна.',
    SERVICE_UNAVAILABLE:'Үйлчилгээ түр ажиллахгүй байна.', NETWORK:'Интернэт холболтоо шалгаад дахин оролдоно уу.',
    FORBIDDEN:'Энэ үйлдлийг хийх эрхгүй байна.', INVALID_INPUT:'Оруулсан мэдээллээ шалгана уу.'
  } as Record<string,string>,
  statuses: {pending:'Жолооч хайж байна', assigned:'Жолооч хуваарилсан', driver_arriving:'Жолооч замд гарсан', arrived:'Жолооч ирсэн', picked_up:'Ачаа авсан', delivered:'Хүргэсэн', completed:'Дууссан', cancelled:'Цуцлагдсан', no_driver_found:'Жолооч олдсонгүй'} as Record<string,string>
};
