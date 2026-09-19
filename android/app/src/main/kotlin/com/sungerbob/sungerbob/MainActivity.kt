package com.sungerbob.sungerbob

import io.flutter.embedding.android.FlutterFragmentActivity

/**
 * `FlutterActivity` değil `FlutterFragmentActivity`.
 *
 * `local_auth` parmak izi ekranını androidx `BiometricPrompt` ile açar ve
 * bu bir `FragmentActivity` ister. Düz `FlutterActivity` ile çağrı cihazda
 * `no_fragment_activity` hatasıyla düşer — testler bunu göremez, çünkü
 * hata yalnızca gerçek cihazda çıkar (D-36).
 */
class MainActivity : FlutterFragmentActivity()
