import 'package:dio/dio.dart';

/// Maps known backend error strings (from FastAPI's HTTPException detail)
/// to plain Bangla. Unknown backend messages are shown as-is (with their
/// HTTP status code) rather than hidden behind a generic message, so a
/// problem we didn't anticipate is still visible and reportable.
const Map<String, String> _knownBackendErrors = {
  'Invalid credentials': 'পাসওয়ার্ড সঠিক নয়।',
  'Invalid role': 'রোলটি সঠিক নয়।',
  'Face not enrolled yet for this spouse':
      'এই ব্যবহারকারীর মুখ এখনো রেজিস্টার করা হয়নি — আগে মুখ রেজিস্ট্রেশন সম্পন্ন করুন।',
  'Face verification failed': 'মুখ মেলেনি — আবার চেষ্টা করুন।',
  'Invalid or expired challenge token':
      'সময় শেষ হয়ে গেছে — প্রথম থেকে আবার চেষ্টা করুন।',
  'Invalid or expired token': 'সেশনের মেয়াদ শেষ হয়ে গেছে — আবার লগইন করুন।',
  'Spouse not found': 'এই ব্যবহারকারীকে খুঁজে পাওয়া যায়নি।',
  'Setup code not found':
      'এই সেটআপ কোডটি খুঁজে পাওয়া যায়নি — বানান ঠিক আছে কিনা দেখুন।',
  'Admin login required': 'অ্যাডমিন লগইন করা লাগবে।',
  'Invalid admin password': 'অ্যাডমিন পাসওয়ার্ড সঠিক নয়।',
  'Reset session not found or expired':
      'রিসেট কোডটি খুঁজে পাওয়া যায়নি বা মেয়াদ শেষ হয়ে গেছে।',
  'An already-logged-in device must approve this reset first':
      'নতুন পাসওয়ার্ড সেট করার আগে অন্য কোনো লগইন করা ডিভাইস থেকে এই রিসেট অনুমোদন করাতে হবে।',
  'Target spouse not found':
      'যার পাসওয়ার্ড পরিবর্তন করতে চাইছেন তাকে খুঁজে পাওয়া যায়নি।',
  'Too many attempts. Please wait a few minutes and try again.':
      'অনেকবার চেষ্টা করা হয়েছে — কিছুক্ষণ অপেক্ষা করে আবার চেষ্টা করুন।',
};

/// Turns any error thrown from an API call into a specific, user-facing
/// Bangla message instead of a generic "something went wrong".
String describeApiError(Object error) {
  if (error is DioException) {
    final response = error.response;
    if (response != null) {
      String? detail;
      final data = response.data;
      if (data is Map && data['detail'] != null) {
        detail = data['detail'].toString();
      }
      final status = response.statusCode;
      if (detail != null) {
        final known = _knownBackendErrors[detail];
        if (known != null) return known;
        return '$detail (স্ট্যাটাস কোড $status)';
      }
      return 'সার্ভার একটা ত্রুটি দিয়েছে (স্ট্যাটাস কোড $status)।';
    }
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'সার্ভারে সংযোগ করতে অনেক সময় লাগছে। ইন্টারনেট সংযোগ ঠিক আছে কিনা দেখুন।';
      case DioExceptionType.connectionError:
        return 'সার্ভারের সাথে সংযোগ করা যায়নি (${error.message ?? "connection error"})। সার্ভার ঠিকানা ও ইন্টারনেট সংযোগ যাচাই করুন।';
      case DioExceptionType.badCertificate:
        return 'সার্ভারের HTTPS সার্টিফিকেট বিশ্বাসযোগ্য নয়।';
      case DioExceptionType.cancel:
        return 'অনুরোধটি বাতিল হয়ে গেছে।';
      default:
        return 'অপ্রত্যাশিত সমস্যা: ${error.message ?? error.toString()}';
    }
  }
  return 'অপ্রত্যাশিত সমস্যা: $error';
}
