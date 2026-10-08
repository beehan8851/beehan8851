# kotlinx.serialization keeps its generated serializers.
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.**
-keepclassmembers class uz.ata.dawnwick.** {
    *** Companion;
}
-keepclasseswithmembers class uz.ata.dawnwick.** {
    kotlinx.serialization.KSerializer serializer(...);
}

# ML Kit finds its components by reflection (ComponentDiscovery) and builds them
# with their no-argument constructors; R8 full mode would strip those.
-keep class * implements com.google.firebase.components.ComponentRegistrar { <init>(); }
-keep class com.google.mlkit.**.*Registrar { <init>(); }

# Crash reports name the file and line (see core/CrashReporter); retrace them with the build's mapping.txt.
-keepattributes SourceFile,LineNumberTable
