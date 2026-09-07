# JNA's Android runtime resolves classes and fields from native code and by
# reflection. Renaming members such as Pointer.peer breaks initialization.
-dontwarn java.awt.**
-keep class com.sun.jna.* { *; }
-keep class * extends com.sun.jna.* { *; }
-keepclassmembers class * extends com.sun.jna.* { public *; }

# Vosk uses JNA direct mapping, so preserve its native bridge signatures too.
-keep class org.vosk.** { *; }
