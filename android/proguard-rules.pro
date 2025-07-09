# Suppress warnings for jcifs and org.ietf.jgss classes
-dontwarn jcifs.Config
-dontwarn jcifs.smb.NtlmPasswordAuthentication
-dontwarn jcifs.smb.SmbNamedPipe
-dontwarn org.ietf.jgss.GSSContext
-dontwarn org.ietf.jgss.GSSCredential
-dontwarn org.ietf.jgss.GSSException
-dontwarn org.ietf.jgss.GSSManager
-dontwarn org.ietf.jgss.GSSName
-dontwarn org.ietf.jgss.Oid

# Suppress warnings for Java invoke classes (Java 9+)
-dontwarn java.lang.invoke.StringConcatFactory
-dontwarn java.lang.invoke.**

# Keep Flutter plugin classes
-keep class com.example.mssql_connection.MssqlConnectionPlugin { *; }
-keep class com.example.mssql_connection.DatabaseManager { *; }
-keep class com.example.mssql_connection.ResultSetSerializer { *; }

# Keep JDBC driver classes
-keep class net.sourceforge.jtds.jdbc.** { *; }
-keep class java.sql.** { *; }

# Keep Jackson JSON processing classes
-keep class com.fasterxml.jackson.** { *; }
-keep @com.fasterxml.jackson.annotation.JsonIgnoreProperties class * { *; }
-keep @com.fasterxml.jackson.annotation.JsonCreator class * { *; }
-keep @com.fasterxml.jackson.annotation.JsonProperty class * { *; }

# Keep Flutter specific classes
-keep class io.flutter.plugin.common.** { *; }
-keep class io.flutter.embedding.** { *; }

# Keep classes that use reflection
-keepclassmembers class * {
    @com.fasterxml.jackson.annotation.JsonCreator *;
    @com.fasterxml.jackson.annotation.JsonProperty *;
}

# Keep SQL related classes
-keep class java.sql.DriverManager { *; }
-keep class java.sql.Connection { *; }
-keep class java.sql.Statement { *; }
-keep class java.sql.ResultSet { *; }
-keep class java.sql.SQLException { *; }

# Keep classes that are accessed via reflection
-keepclassmembers class * extends java.sql.Driver {
    <init>();
}

# Keep all classes in the main plugin package
-keep class com.example.mssql_connection.** { *; }

# Keep Kotlin coroutines classes
-keep class kotlinx.coroutines.** { *; }
-dontwarn kotlinx.coroutines.**

# Keep multidex classes
-keep class androidx.multidex.** { *; }