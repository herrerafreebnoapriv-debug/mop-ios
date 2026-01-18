# Flutter 混淆规则
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# 保留原生代码
-keep class com.mop.app.** { *; }

# 保留数据模型
-keep class * implements java.io.Serializable { *; }
-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}

# 保留注解
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes Exceptions

# 保留 Jitsi Meet
-keep class org.jitsi.meet.** { *; }

# 保留 Socket.io
-keep class io.socket.** { *; }

# 保留加密库
-keep class org.bouncycastle.** { *; }
