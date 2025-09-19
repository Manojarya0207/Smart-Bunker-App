import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:provider/provider.dart' as provider_lib;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:collection/collection.dart'; // For firstWhereOrNull
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';

/// The main entry point of the Flutter application.
void main() {
  runApp(const MyApp());
}

/// Enum to define user roles.
enum UserRole {
  student,
  teacher,
  unselected, // Default state before a role is chosen
}

/// Data model for application-wide settings.
/// Now includes persistence for notification settings.
class AppSettings extends ChangeNotifier {
  ThemeMode _selectedThemeMode;
  final String _appName;
  bool _dailyReminderEnabled;
  DateTime? _lastReminderDate;

  late SharedPreferences _prefs;
  static const String _dailyReminderEnabledKey = 'dailyReminderEnabled';
  static const String _lastReminderDateKey = 'lastReminderDate';
  static const String _selectedThemeModeKey = 'selectedThemeMode';

  AppSettings({
    ThemeMode selectedThemeMode = ThemeMode.light,
    String appName = 'Smart Bunker',
    bool dailyReminderEnabled = true,
    DateTime? lastReminderDate,
  })  : _selectedThemeMode = selectedThemeMode,
        _appName = appName,
        _dailyReminderEnabled = dailyReminderEnabled,
        _lastReminderDate = lastReminderDate {
    _initPrefsAndLoadData();
  }

  ThemeMode get selectedThemeMode => _selectedThemeMode;
  String get appName => _appName;
  bool get dailyReminderEnabled => _dailyReminderEnabled;
  DateTime? get lastReminderDate => _lastReminderDate;

  set selectedThemeMode(ThemeMode newValue) {
    if (_selectedThemeMode != newValue) {
      _selectedThemeMode = newValue;
      _savePrefs(); // Save theme mode
      notifyListeners();
    }
  }

  set dailyReminderEnabled(bool newValue) {
    if (_dailyReminderEnabled != newValue) {
      _dailyReminderEnabled = newValue;
      _savePrefs();
      notifyListeners();
    }
  }

  set lastReminderDate(DateTime? newValue) {
    if (_lastReminderDate != newValue) {
      _lastReminderDate = newValue;
      _savePrefs();
      notifyListeners();
    }
  }

  Future<void> _initPrefsAndLoadData() async {
    _prefs = await SharedPreferences.getInstance();
    _dailyReminderEnabled = _prefs.getBool(_dailyReminderEnabledKey) ?? true;
    final String? lastReminderDateString = _prefs.getString(
      _lastReminderDateKey,
    );
    if (lastReminderDateString != null) {
      _lastReminderDate = DateTime.tryParse(lastReminderDateString);
    }
    final String? themeModeString = _prefs.getString(_selectedThemeModeKey);
    _selectedThemeMode = ThemeMode.values.firstWhere(
      (ThemeMode e) => e.name == themeModeString,
      orElse: () => ThemeMode.light,
    );
    notifyListeners();
  }

  Future<void> _savePrefs() async {
    await _prefs.setBool(_dailyReminderEnabledKey, _dailyReminderEnabled);
    if (_lastReminderDate != null) {
      await _prefs.setString(
        _lastReminderDateKey,
        _lastReminderDate!.toIso8601String(),
      );
    } else {
      await _prefs.remove(_lastReminderDateKey);
    }
    await _prefs.setString(_selectedThemeModeKey, _selectedThemeMode.name);
  }

  // Provides the formatted TextSpan for sharing the app information.
  TextSpan getShareMessageTextSpan() {
    return TextSpan(
      children: <TextSpan>[
        const TextSpan(text: 'Check out '),
        TextSpan(
          text: _appName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const TextSpan(
          text:
              ' – your ultimate attendance management app! Download it today!',
        ),
      ],
    );
  }
}

/// DATA_MODEL
/// Manages user session (specifically, the selected role).
/// Persists the selected role using SharedPreferences.
class UserSession extends ChangeNotifier {
  UserRole _userRole;

  late SharedPreferences _prefs;
  static const String _userRoleKey = 'userRole';

  UserSession({UserRole userRole = UserRole.unselected})
      : _userRole = userRole {
    _initPrefsAndLoadData();
  }

  Future<void> _initPrefsAndLoadData() async {
    _prefs = await SharedPreferences.getInstance();
    final String? roleString = _prefs.getString(_userRoleKey);
    _userRole = UserRole.values.firstWhere(
      (UserRole e) => e.name == roleString,
      orElse: () => UserRole.unselected,
    );
    notifyListeners(); // Notify after loading initial state
  }

  bool get isLoggedIn => _userRole != UserRole.unselected;
  UserRole get userRole => _userRole;

  set userRole(UserRole newValue) {
    if (_userRole != newValue) {
      _userRole = newValue;
      _saveState();
      notifyListeners();
    }
  }

  Future<void> _saveState() async {
    await _prefs.setString(_userRoleKey, _userRole.name);
  }
}

/// DATA_MODEL
/// Represents a student with a name and a register number, for the Student's perspective.
class StudentSubject {
  final String name;
  final String subjectCode; // A code for the subject

  const StudentSubject({
    required this.name,
    required this.subjectCode, // Made required
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StudentSubject &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          subjectCode == other.subjectCode;

  @override
  int get hashCode => Object.hash(name, subjectCode);

  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        'subjectCode': subjectCode,
      };

  factory StudentSubject.fromJson(Map<String, dynamic> json) {
    return StudentSubject(
      name: json['name'] as String,
      subjectCode: json['subjectCode'] as String,
    );
  }
}

/// DATA_MODEL
/// Data model for managing subjects for a student.
/// This model uses SharedPreferences for persistence.
class StudentSubjectsModel extends ChangeNotifier {
  List<StudentSubject> _subjects;

  late SharedPreferences _prefs;
  static const String _subjectsKey = 'studentSubjects';

  StudentSubjectsModel({List<StudentSubject>? initialSubjects})
      : _subjects = initialSubjects ?? <StudentSubject>[] {
    _initPrefsAndLoadData();
  }

  Future<void> _initPrefsAndLoadData() async {
    _prefs = await SharedPreferences.getInstance();
    await _loadSubjects();
    if (_subjects.isEmpty) {
      _subjects.addAll(<StudentSubject>[]);
      await _saveSubjects();
    }
    notifyListeners();
  }

  List<StudentSubject> get subjects =>
      List<StudentSubject>.unmodifiable(_subjects);

  void addSubject(String name, String subjectCode) {
    final String trimmedName = name.trim();
    final String trimmedCode = subjectCode.trim();

    if (trimmedName.isNotEmpty && trimmedCode.isNotEmpty) {
      final StudentSubject newSubject = StudentSubject(
        name: trimmedName,
        subjectCode: trimmedCode,
      );
      if (!_subjects.any(
        (StudentSubject s) =>
            s.name == newSubject.name &&
            s.subjectCode == newSubject.subjectCode,
      )) {
        _subjects.add(newSubject);
        _subjects.sort(
          (StudentSubject a, StudentSubject b) =>
              a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
        _saveSubjects();
        notifyListeners();
      } else {
        debugPrint(
          'Student Subject "$trimmedName" with code "$trimmedCode" already exists.',
        );
      }
    }
  }

  void removeSubject(StudentSubject subject) {
    if (_subjects.remove(subject)) {
      _saveSubjects();
      notifyListeners();
    }
  }

  /// Clears all subjects for the current student.
  Future<void> clearAllSubjects() async {
    _subjects.clear();
    await _saveSubjects();
    notifyListeners();
  }

  Future<void> _saveSubjects() async {
    final List<Map<String, dynamic>> subjectsJson = _subjects
        .map<Map<String, dynamic>>((StudentSubject s) => s.toJson())
        .toList();
    await _prefs.setString(_subjectsKey, jsonEncode(subjectsJson));
  }

  Future<void> _loadSubjects() async {
    final String? subjectsString = _prefs.getString(_subjectsKey);
    if (subjectsString != null) {
      try {
        final List<dynamic> subjectsJson =
            jsonDecode(subjectsString) as List<dynamic>;
        _subjects = subjectsJson
            .map<StudentSubject>(
              (dynamic item) =>
                  StudentSubject.fromJson(item as Map<String, dynamic>),
            )
            .toList();
        _subjects.sort(
          (StudentSubject a, StudentSubject b) =>
              a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
      } catch (e) {
        debugPrint(
          'Error loading student subjects: $e. Clearing corrupted data.',
        );
        _subjects.clear();
      }
    }
  }
}

/// DATA_MODEL
/// Represents a student with a name and a register number.
/// This model is shared between Teacher and Student. Teachers manage a list of these.
/// Students manage a single instance of this as their profile.
class Student {
  final String name;
  final String registerNumber;

  const Student({required this.name, this.registerNumber = ''});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Student &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          registerNumber == other.registerNumber;

  @override
  int get hashCode => Object.hash(name, registerNumber);

  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        'registerNumber': registerNumber,
      };

  factory Student.fromJson(Map<String, dynamic> json) {
    return Student(
      name: json['name'] as String,
      registerNumber: json['registerNumber'] as String? ?? '',
    );
  }
}

/// DATA_MODEL
/// Manages the *single* student profile for the current app user when they are in 'student' role.
/// This replaces the student's personal profile from being part of the general StudentData list.
class CurrentStudentProfile extends ChangeNotifier {
  Student? _profile;

  late SharedPreferences _prefs;
  static const String _profileKey = 'currentStudentProfile';

  CurrentStudentProfile({Student? initialProfile}) : _profile = initialProfile {
    _initPrefsAndLoadData();
  }

  Future<void> _initPrefsAndLoadData() async {
    _prefs = await SharedPreferences.getInstance();
    await _loadProfile();
    notifyListeners();
  }

  Student? get profile => _profile;

  Future<void> setProfile(Student? newProfile) async {
    if (_profile != newProfile) {
      _profile = newProfile;
      await _saveProfile();
      notifyListeners();
    }
  }

  Future<void> clearProfile() async {
    _profile = null;
    await _prefs.remove(_profileKey);
    notifyListeners();
  }

  Future<void> _saveProfile() async {
    if (_profile != null) {
      await _prefs.setString(_profileKey, jsonEncode(_profile!.toJson()));
    } else {
      await _prefs.remove(_profileKey);
    }
  }

  Future<void> _loadProfile() async {
    final String? profileString = _prefs.getString(_profileKey);
    if (profileString != null && profileString.isNotEmpty) {
      try {
        _profile = Student.fromJson(
          jsonDecode(profileString) as Map<String, dynamic>,
        );
      } catch (e) {
        debugPrint(
          'Error loading student profile: $e. Clearing corrupted data.',
        );
        _profile = null;
        await _prefs.remove(_profileKey);
      }
    } else {
      _profile = null;
    }
  }
}

/// DATA_MODEL
/// Data model for managing students for a teacher.
/// This data persists using SharedPreferences.
class StudentData extends ChangeNotifier {
  List<Student> _students;

  late SharedPreferences _prefs;
  static const String _studentsKey = 'studentList';

  StudentData({List<Student>? initialStudents})
      : _students = initialStudents ?? <Student>[] {
    _initPrefsAndLoadData();
  }

  Future<void> _initPrefsAndLoadData() async {
    _prefs = await SharedPreferences.getInstance();
    await _loadStudents();
    if (_students.isEmpty) {
      _students.addAll(<Student>[]);
      await _saveStudents();
    }
    notifyListeners();
  }

  List<Student> get students => List<Student>.unmodifiable(_students);

  void addStudent(String name, String registerNumber) {
    final String trimmedName = name.trim();
    final String trimmedRegNum = registerNumber.trim();
    if (trimmedName.isNotEmpty) {
      // Only name is strictly required for adding
      final Student newStudent = Student(
        name: trimmedName,
        registerNumber: trimmedRegNum, // Can be empty
      );
      if (!_students.any(
        (Student s) =>
            s.name == newStudent.name &&
            s.registerNumber == newStudent.registerNumber,
      )) {
        _students.add(newStudent);
        // Sort the students list numerically by register number, then by name
        _sortStudents();
        _saveStudents();
        notifyListeners();
      } else {
        debugPrint(
          'Student "$trimmedName" with register number "$trimmedRegNum" already exists.',
        );
      }
    }
  }

  void removeStudent(Student student) {
    if (_students.remove(student)) {
      _saveStudents();
      notifyListeners();
    }
  }

  Future<void> _saveStudents() async {
    final List<Map<String, dynamic>> studentsJson = _students
        .map<Map<String, dynamic>>((Student s) => s.toJson())
        .toList();
    await _prefs.setString(_studentsKey, jsonEncode(studentsJson));
  }

  Future<void> _loadStudents() async {
    final String? studentsString = _prefs.getString(_studentsKey);
    if (studentsString != null) {
      try {
        final List<dynamic> studentsJson =
            jsonDecode(studentsString) as List<dynamic>;
        _students = studentsJson
            .map<Student>(
              (dynamic item) => Student.fromJson(item as Map<String, dynamic>),
            )
            .toList();
        // Ensure initial load is also sorted
        _sortStudents();
      } catch (e) {
        debugPrint('Error loading students: $e. Clearing corrupted data.');
        _students.clear(); // Clear data if overall decoding or structure is bad
      }
    }
  }

  // Helper method to sort students by register number (numeric then alphanumeric) then by name.
  void _sortStudents() {
    _students.sort((Student a, Student b) {
      final bool aHasRegNum = a.registerNumber.isNotEmpty;
      final bool bHasRegNum = b.registerNumber.isNotEmpty;

      if (!aHasRegNum && !bHasRegNum) {
        // Both empty or neither has reg num, sort by name
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      }
      if (!aHasRegNum) return 1; // Empty reg num comes after non-empty
      if (!bHasRegNum) return -1; // Non-empty reg num comes before empty

      // Both have register numbers, attempt numeric comparison
      final int? aNum = int.tryParse(a.registerNumber);
      final int? bNum = int.tryParse(b.registerNumber);

      if (aNum != null && bNum != null) {
        // Both are pure numbers, compare numerically
        return aNum.compareTo(bNum);
      } else if (aNum != null) {
        return -1; // Numeric before alpha-numeric
      } else if (bNum != null) {
        return 1; // Alpha-numeric after numeric
      } else {
        // Both are non-numeric strings, sort lexicographically
        return a.registerNumber
            .toLowerCase()
            .compareTo(b.registerNumber.toLowerCase());
      }
    });
  }
}

/// The root widget of the application.
/// Sets up the MaterialApp and provides AppSettings and other shared models.
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return provider_lib.ChangeNotifierProvider<AppSettings>(
      create: (BuildContext context) => AppSettings(),
      builder: (BuildContext providerContext, Widget? child) {
        return provider_lib.ChangeNotifierProvider<UserSession>(
          create: (BuildContext userSessionContext) => UserSession(),
          builder: (
            BuildContext userSessionProviderContext,
            Widget? userSessionChild,
          ) {
            return provider_lib.MultiProvider(
              providers: <provider_lib.ChangeNotifierProvider<ChangeNotifier>>[
                provider_lib.ChangeNotifierProvider<TeacherSubjectsData>(
                  create: (BuildContext multiProviderCreateContext) =>
                      TeacherSubjectsData(),
                ),
                provider_lib.ChangeNotifierProvider<StudentData>(
                  create: (BuildContext multiProviderCreateContext) =>
                      StudentData(),
                ),
                // Provide CurrentStudentProfile for the student user
                provider_lib.ChangeNotifierProvider<CurrentStudentProfile>(
                  create: (BuildContext multiProviderCreateContext) =>
                      CurrentStudentProfile(),
                ),
                provider_lib.ChangeNotifierProvider<StudentSubjectsModel>(
                  create: (BuildContext multiProviderCreateContext) =>
                      StudentSubjectsModel(),
                ),
                provider_lib.ChangeNotifierProvider<AttendanceData>(
                  create: (BuildContext multiProviderCreateContext) =>
                      AttendanceData(),
                ),
              ],
              builder: (
                BuildContext multiProviderBuilderContext,
                Widget? multiProviderBuilderChild,
              ) {
                // Consumer for AppSettings to react to theme changes
                return provider_lib.Consumer<AppSettings>(
                  builder: (
                    BuildContext appSettingsConsumerContext,
                    AppSettings appSettings,
                    Widget? appSettingsConsumerChild,
                  ) {
                    return MaterialApp(
                      debugShowCheckedModeBanner: false,
                      title: appSettings.appName,
                      theme: ThemeData(
                        primarySwatch: Colors.blue,
                        visualDensity: VisualDensity.adaptivePlatformDensity,
                        colorScheme: ColorScheme.fromSwatch(
                          primarySwatch: Colors.blue,
                        ).copyWith(
                          primary: Colors.blue.shade700,
                          secondary: Colors.lightBlue.shade600,
                          surface: Colors.white,
                          onPrimary: Colors.white,
                          onSecondary: Colors.white,
                          onSurface: Colors.black,
                          error: Colors.red.shade700,
                          onError: Colors.white,
                        ),
                        appBarTheme: AppBarTheme(
                          backgroundColor: Colors.blue.shade700,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          titleTextStyle: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        brightness: Brightness.light,
                        cardColor: Colors.white,
                      ),
                      darkTheme: ThemeData(
                        primarySwatch: Colors.blue,
                        visualDensity: VisualDensity.adaptivePlatformDensity,
                        colorScheme: ColorScheme.fromSwatch(
                          primarySwatch: Colors.blue,
                          brightness: Brightness.dark,
                        ).copyWith(
                          primary: Colors.blue.shade400,
                          secondary: Colors.lightBlue.shade300,
                          surface: const Color(0xFF121212),
                          onPrimary: Colors.black,
                          onSecondary: Colors.black,
                          onSurface: Colors.white,
                          error: Colors.red.shade400,
                          onError: Colors.black,
                        ),
                        appBarTheme: AppBarTheme(
                          backgroundColor: Colors.blue.shade900,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          titleTextStyle: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        brightness: Brightness.dark,
                        cardColor: const Color(0xFF1E1E1E),
                      ),
                      themeMode: appSettings.selectedThemeMode,
                      home:
                          const MainAppScreen(), // First screen is MainAppScreen now
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

/// The main screen which handles the initial splash and home page display.
class MainAppScreen extends StatefulWidget {
  const MainAppScreen({super.key});

  @override
  State<MainAppScreen> createState() => _MainAppScreenState();
}

class _MainAppScreenState extends State<MainAppScreen> {
  // Controls the transition from initial splash to home UI.
  bool _showHomeUI = false;
  // Store the current date and time for the AppBar title.
  late DateTime _currentDateTime;

  Timer? _notificationTimer;

  @override
  void initState() {
    super.initState();
    _currentDateTime = DateTime.now();

    // Simulate an initial app loading delay before showing the home UI.
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _showHomeUI = true;
        });
        _scheduleDailyNotificationCheck(); // Start checking for reminders after splash
      }
    });
  }

  @override
  void dispose() {
    _notificationTimer
        ?.cancel(); // Cancel the timer when the widget is disposed
    super.dispose();
  }

  void _scheduleDailyNotificationCheck() {
    // Check every minute if it's time to show the reminder.
    _notificationTimer = Timer.periodic(const Duration(minutes: 1), (
      Timer timer,
    ) {
      _checkAndShowAttendanceReminder();
    });
  }

  void _checkAndShowAttendanceReminder() {
    if (!mounted) {
      _notificationTimer?.cancel();
      return;
    }

    final AppSettings appSettings = provider_lib.Provider.of<AppSettings>(
      context,
      listen: false,
    );
    final UserSession userSession = provider_lib.Provider.of<UserSession>(
      context,
      listen: false,
    );
    final AttendanceData attendanceData =
        provider_lib.Provider.of<AttendanceData>(context, listen: false);
    final StudentSubjectsModel studentSubjectsModel =
        provider_lib.Provider.of<StudentSubjectsModel>(context, listen: false);
    final CurrentStudentProfile currentStudentProfile =
        provider_lib.Provider.of<CurrentStudentProfile>(context, listen: false);

    if (!appSettings.dailyReminderEnabled || !userSession.isLoggedIn) {
      return; // Don't show if disabled or no role selected yet
    }

    final DateTime now = DateTime.now();
    final DateTime today = DateUtils.dateOnly(now);

    // Check if reminder was already shown today
    if (appSettings.lastReminderDate != null &&
        DateUtils.dateOnly(appSettings.lastReminderDate!) == today) {
      debugPrint('Reminder already shown today for ${userSession.userRole}.');
      return;
    }

    // Check if it's around 2:00 PM (14:00)
    if (now.hour == 14 && now.minute >= 0 && now.minute < 5) {
      String title = "Attendance Reminder";
      String message = ''; // Initialize message to an empty string
      bool shouldShow = true;

      if (userSession.userRole == UserRole.student) {
        final Student? currentStudent = currentStudentProfile.profile;
        if (currentStudent != null) {
          final List<StudentSubject> studentEnrolledSubjects =
              studentSubjectsModel.subjects;
          const String generalSubjectCode =
              'GENERAL'; // Special code for general attendance

          bool allAttendanceMarked =
              true; // Overall flag for all subjects + general attendance

          // Check General Attendance
          final AttendanceStatus generalStatus = attendanceData.getAttendance(
            today,
            currentStudent.registerNumber,
            generalSubjectCode,
          );
          if (generalStatus == AttendanceStatus.noclass) {
            allAttendanceMarked = false;
          }

          // Check subject-specific attendance only if general is marked or there are no subjects
          if (allAttendanceMarked && studentEnrolledSubjects.isNotEmpty) {
            for (final StudentSubject subject in studentEnrolledSubjects) {
              final AttendanceStatus status = attendanceData.getAttendance(
                today,
                currentStudent.registerNumber,
                subject.subjectCode,
              );
              if (status == AttendanceStatus.noclass) {
                allAttendanceMarked = false;
                break;
              }
            }
          }

          if (allAttendanceMarked) {
            shouldShow = false; // All attendance for today (general + subjects) is marked
            debugPrint('Student attendance fully marked, no reminder needed.');
          } else if (studentEnrolledSubjects.isEmpty &&
              generalStatus == AttendanceStatus.noclass) {
            message =
                "You have no subjects added and general attendance is not marked. Please add your subjects and mark general attendance!";
          } else if (generalStatus == AttendanceStatus.noclass) {
            message =
                "Your general attendance for today hasn't been marked. Please submit!";
          } else {
            message =
                "Some of your class attendance for today hasn't been marked. Please submit!";
          }
        } else {
          message =
              "Your student profile is not set up. Please add it to mark attendance.";
        }
      } else if (userSession.userRole == UserRole.teacher) {
        // For teachers, a general reminder to mark attendance for students
        message =
            "Don't forget to mark student attendance for your classes today!";
      } else {
        // If role is unselected, remind to select role
        message =
            "Please select your role (Teacher/Student) to start using the app and manage attendance.";
      }

      if (shouldShow) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$title: $message'),
            duration: const Duration(seconds: 1, milliseconds: 500),
            action: SnackBarAction(
              label: 'Dismiss',
              onPressed: () {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
              },
            ),
          ),
        );
        appSettings.lastReminderDate =
            today; // Mark reminder as shown for today
        debugPrint('Attendance reminder shown for ${userSession.userRole}.');
      }
    }
  }

  // Helper to format the current date and day.
  String _getFormattedDateAndDay() {
    final String weekday = DateFormat(
      'EEEE',
    ).format(_currentDateTime); // e.g., Monday
    final String date = DateFormat(
      'MMMM d, y',
    ).format(_currentDateTime); // e.g., July 22, 2024
    return '$weekday, $date';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        elevation: 0, // Keep splash screen app bar flat
        leading: _showHomeUI
            ? Padding(
                padding: const EdgeInsets.all(8.0),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const AppIcon(size: 24),
                ),
              )
            : null,
        title: _showHomeUI
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(
                    _getFormattedDateAndDay(),
                    style: TextStyle(
                      color: Theme.of(context).appBarTheme.foregroundColor,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              )
            : const AppLogoHeader(),
        automaticallyImplyLeading: false,
      ),
      body: _showHomeUI
          ? const RoleSelectionPage() // Changed from HomePage() to RoleSelectionPage()
          : const AppSplashContent(),
    );
  }
}

/// Displays the initial app splash content, including the centered logo and text.
class AppSplashContent extends StatefulWidget {
  const AppSplashContent({super.key});

  @override
  State<AppSplashContent> createState() => _AppSplashContentState();
}

class _AppSplashContentState extends State<AppSplashContent>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _logoScaleAnimation;
  late Animation<double> _logoFadeAnimation;
  late Animation<double> _textFadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500), // Animation duration
    );

    _logoScaleAnimation = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.elasticOut, // Slightly bouncy scale
      ),
    );

    _logoFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(
          0.0,
          0.7,
          curve: Curves.easeIn,
        ), // Fade in during the first 70% of animation
      ),
    );

    _textFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(
          0.4,
          1.0,
          curve: Curves.easeIn,
        ), // Start fading text in after logo has started
      ),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      // Wrapped the Column in Center to ensure it's centered horizontally and vertically.
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          FadeTransition(
            opacity: _logoFadeAnimation,
            child: ScaleTransition(
              scale: _logoScaleAnimation,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const AppIcon(size: 120),
              ),
            ),
          ),
          const SizedBox(height: 20),
          FadeTransition(
            opacity: _textFadeAnimation,
            child: Text(
              "Smart",
              style: TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(height: 8),
          FadeTransition(
            opacity: _textFadeAnimation, // Using the same text fade animation
            child: Text(
              "BUNKER", // Changed text here
              style: TextStyle(
                fontSize: 25,
                color: Theme.of(context).colorScheme.onSurface,
                letterSpacing: 2,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Displays the app logo and title prominently in the AppBar.
class AppLogoHeader extends StatelessWidget {
  const AppLogoHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize
          .max, // FIX: Changed from min to max to fill available AppBar title space.
      children: <Widget>[
        // Logo Icon part
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const AppIcon(size: 24),
        ),
        const SizedBox(width: 8),
        // Text part of the logo
        Expanded(
          // Added Expanded to allow text to take available space
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                "Smart",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).appBarTheme.foregroundColor,
                ),
                overflow: TextOverflow.ellipsis, // Added overflow handling
              ),
              Text(
                "BUNKER", // Changed text here
                style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context).appBarTheme.foregroundColor,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis, // Added overflow handling
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Custom widget to approximate the app's unique icon.
/// Combines a graduation cap icon with a checkmark.
class AppIcon extends StatelessWidget {
  final double size;
  const AppIcon({super.key, this.size = 80});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.bottomRight,
      children: <Widget>[
        // Main icon representing a student with a graduation cap.
        Icon(Icons.school, color: Colors.white, size: size),
        // Checkmark icon overlaid on the student icon.
        Positioned(
          right: 0,
          bottom: 0,
          child: Icon(
            Icons.check_circle,
            color: Colors.greenAccent,
            size: size * 0.4,
          ),
        ),
      ],
    );
  }
}

/// A page that allows the user to select their role (Teacher or Student).
class RoleSelectionPage extends StatelessWidget {
  const RoleSelectionPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(
            "Welcome to Smart Bunker!", // Changed text here
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            "Please select your role to continue:",
            style: TextStyle(
              fontSize: 16,
              color: Theme.of(context).colorScheme.onSurface.withAlpha(178),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 40),
          SizedBox(
            width: 200, // Fixed width for buttons
            child: ElevatedButton.icon(
              onPressed: () {
                provider_lib.Provider.of<UserSession>(
                  context,
                  listen: false,
                ).userRole = UserRole.teacher;
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (BuildContext context) => const TeachersPage(),
                  ),
                );
              },
              icon: const Icon(Icons.school),
              label: const Text("Teacher"),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 15,
                ),
                textStyle: const TextStyle(fontSize: 20),
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
              ),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: 200, // Fixed width for buttons
            child: ElevatedButton.icon(
              onPressed: () {
                provider_lib.Provider.of<UserSession>(
                  context,
                  listen: false,
                ).userRole = UserRole.student;
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (BuildContext routeContext) =>
                        const StudentsMainScreen(), // Changed to StudentsMainScreen
                  ),
                );
              },
              icon: const Icon(Icons.person),
              label: const Text("Student"),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 15,
                ),
                textStyle: const TextStyle(fontSize: 20),
                backgroundColor: Theme.of(context).colorScheme.secondary,
                foregroundColor: Theme.of(context).colorScheme.onSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Displays overall attendance summaries for teachers.
/// This page allows teachers to see an overview of student attendance and search.
class TeacherStudentOverallAttendancePage extends StatefulWidget {
  const TeacherStudentOverallAttendancePage({super.key});

  @override
  State<TeacherStudentOverallAttendancePage> createState() =>
      _TeacherStudentOverallAttendancePageState();
}

class _TeacherStudentOverallAttendancePageState
    extends State<TeacherStudentOverallAttendancePage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchText = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      _searchText = _searchController.text;
    });
  }

  /// Calculates the general attendance percentage for a given student for the 'GENERAL' subject code.
  /// Counts 'present' as 1, 'halfday' as 0.5. 'Absent' is 0. 'noclass' is not counted in total days.
  double _calculateGeneralAttendancePercentage(
    String studentRegisterNumber,
    AttendanceData attendanceData,
  ) {
    const String generalSubjectCode = 'GENERAL';
    final Map<DateTime, AttendanceStatus> generalSubjectRecords =
        attendanceData.getStudentAttendanceForSubject(
      studentRegisterNumber,
      generalSubjectCode,
    );

    if (generalSubjectRecords.isEmpty) {
      return 0.0;
    }

    double totalPresentDays = 0.0;
    int totalAttendanceDaysConsidered =
        0; // Days where class was held and attendance was marked present/absent/halfday

    generalSubjectRecords.forEach((DateTime date, AttendanceStatus status) {
      if (status != AttendanceStatus.noclass) {
        totalAttendanceDaysConsidered++;
        if (status == AttendanceStatus.present) {
          totalPresentDays += 1.0;
        } else if (status == AttendanceStatus.halfday) {
          totalPresentDays += 0.5;
        }
        // Absent status implicitly adds 0 to totalPresentDays
      }
    });

    if (totalAttendanceDaysConsidered == 0) return 0.0;
    return (totalPresentDays / totalAttendanceDaysConsidered) * 100.0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Overall Student Attendance Summary'),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        foregroundColor: Theme.of(context).appBarTheme.foregroundColor,
        elevation: 4, // Added elevation
      ),
      body: provider_lib.Consumer2<StudentData, AttendanceData>(
        builder: (
          BuildContext context,
          StudentData studentData,
          AttendanceData attendanceData,
          Widget? child,
        ) {
          final List<Student> filteredStudents = studentData.students.where(
            (Student student) {
              final String lowerCaseSearchText = _searchText.toLowerCase();
              return student.name.toLowerCase().contains(
                        lowerCaseSearchText,
                      ) ||
                  student.registerNumber.toLowerCase().contains(
                        lowerCaseSearchText,
                      );
            },
          ).toList();

          if (studentData.students.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(
                    Icons.group_off,
                    size: 80,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withAlpha(100),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    "No students added to track attendance yet.",
                    style: TextStyle(
                      fontSize: 18,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withAlpha(178),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }
          return Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    labelText: 'Search Student by Name or Register No.',
                    hintText: 'Type to search...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchText.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                    floatingLabelStyle: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.0),
                      borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.primary,
                        width: 2.0,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: filteredStudents.isEmpty && _searchText.isNotEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            Icon(
                              Icons.search_off,
                              size: 60,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withAlpha(100),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              "No results found for '$_searchText'.",
                              style: TextStyle(
                                fontSize: 16,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withAlpha(178),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16.0,
                          vertical: 8.0,
                        ),
                        itemCount: filteredStudents.length,
                        itemBuilder: (BuildContext listContext, int index) {
                          final Student student = filteredStudents[index];
                          // Use the new method to calculate general attendance percentage
                          final double percentage =
                              _calculateGeneralAttendancePercentage(
                                student.registerNumber,
                                attendanceData,
                              );

                          return Card(
                            margin: const EdgeInsets.symmetric(
                              vertical: 4.0,
                            ),
                            elevation: 4,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(
                                8.0,
                              ), // Reduced padding
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    student.name,
                                    style: TextStyle(
                                      fontSize: 16, // Reduced font size
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(
                                        listContext,
                                      ).colorScheme.onSurface,
                                    ),
                                  ),
                                  const SizedBox(
                                    height: 2,
                                  ), // Reduced height
                                  Text(
                                    student.registerNumber.isNotEmpty
                                        ? 'Reg. No: ${student.registerNumber}'
                                        : 'No Register Number',
                                    style: TextStyle(
                                      fontSize: 12, // Reduced font size
                                      color: Theme.of(listContext)
                                          .colorScheme
                                          .onSurface
                                          .withAlpha(178),
                                    ),
                                  ),
                                  const SizedBox(
                                    height: 6,
                                  ), // Reduced height
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: <Widget>[
                                      Text(
                                        'General Attendance:', // Changed text here
                                        style: TextStyle(
                                          fontSize: 13, // Reduced font size
                                          color: Theme.of(
                                            listContext,
                                          ).colorScheme.onSurface,
                                        ),
                                      ),
                                      Text(
                                        '${percentage.toStringAsFixed(1)}%',
                                        style: TextStyle(
                                          fontSize: 15, // Reduced font size
                                          fontWeight: FontWeight.bold,
                                          color: percentage >= 75
                                              ? Colors.green.shade500
                                              : percentage >= 50
                                                  ? Colors.orange.shade500
                                                  : Colors.red.shade500,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(
                                    height: 4,
                                  ), // Reduced height
                                  ClipRRect(
                                    // Wrap LinearProgressIndicator with ClipRRect for borderRadius
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: percentage / 100,
                                      backgroundColor: Theme.of(
                                        listContext,
                                      ).colorScheme.onSurface.withAlpha(50),
                                      color: percentage >= 75
                                          ? Colors.green.shade500
                                          : percentage >= 50
                                              ? Colors.orange.shade500
                                              : Colors.red.shade500,
                                      minHeight: 4, // Reduced minHeight
                                    ),
                                  ),
                                  const SizedBox(
                                    height: 8,
                                  ), // Reduced height
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: ElevatedButton.icon(
                                      onPressed: () {
                                        Navigator.push(
                                          listContext,
                                          MaterialPageRoute<void>(
                                            builder: (BuildContext context) =>
                                                StudentAttendanceGraphPage(
                                                  student: student,
                                                ),
                                          ),
                                        );
                                      },
                                      icon: const Icon(Icons.bar_chart),
                                      label: const Text('View More'),
                                      style: ElevatedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical:
                                              8, // Reduced vertical padding
                                        ),
                                        textStyle: const TextStyle(
                                          fontSize: 13, // Reduced font size
                                        ),
                                        backgroundColor: Theme.of(
                                          listContext,
                                        ).colorScheme.secondary,
                                        foregroundColor: Theme.of(
                                          listContext,
                                        ).colorScheme.onSecondary,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The student's personal attendance page, allowing selection if multiple students exist.
class MyAttendancePage extends StatefulWidget {
  const MyAttendancePage({super.key});

  @override
  State<MyAttendancePage> createState() => _MyAttendancePageState();
}

class _MyAttendancePageState extends State<MyAttendancePage> {
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _selectedDate = DateUtils.dateOnly(DateTime.now()); // Ensure date only
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
      helpText: 'Select Attendance Date',
      cancelText: 'Cancel',
      confirmText: 'Select',
      builder: (BuildContext context, Widget? child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: ColorScheme.light(
              primary: Theme.of(context).colorScheme.primary,
              onPrimary: Theme.of(context).colorScheme.onPrimary,
              surface: Theme.of(context).colorScheme.surface,
              onSurface: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && DateUtils.dateOnly(picked) != _selectedDate) {
      setState(() {
        _selectedDate = DateUtils.dateOnly(picked);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Attendance date set to: ${DateFormat('EEEE, MMMM d, y').format(_selectedDate)}',
          ),
          duration: const Duration(seconds: 1, milliseconds: 500),
        ),
      );
    }
  }

  Color _getCardColor(AttendanceStatus status, ThemeData theme) {
    switch (status) {
      case AttendanceStatus.present:
        return Colors.green.shade500.withAlpha(51);
      case AttendanceStatus.absent:
        return Colors.red.shade500.withAlpha(26);
      case AttendanceStatus.halfday: // New case for Half Day
        return Colors.orange.shade300.withAlpha(51);
      case AttendanceStatus.noclass: // Previously unknown/halfday
        return theme.cardColor; // Default card color for 'No Class'
    }
  }

  // Helper to get text for attendance status
  String _getStatusText(AttendanceStatus status) {
    switch (status) {
      case AttendanceStatus.present:
        return 'Present';
      case AttendanceStatus.absent:
        return 'Absent';
      case AttendanceStatus.halfday:
        return 'Half Day';

      case AttendanceStatus.noclass:
        return 'No Class'; // Explicitly return for noclass
    }
  }

  @override
  Widget build(BuildContext context) {
    return provider_lib.Consumer3<
        CurrentStudentProfile, // Use CurrentStudentProfile instead of StudentData
        StudentSubjectsModel,
        AttendanceData>(
      builder: (
        BuildContext consumerContext,
        CurrentStudentProfile currentStudentProfile,
        StudentSubjectsModel studentSubjectsModel,
        AttendanceData attendanceData,
        Widget? child,
      ) {
        final Student? selectedStudent = currentStudentProfile.profile;
        const String generalSubjectCode = 'GENERAL';

        if (selectedStudent == null) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(
                  Icons.person_off,
                  size: 80,
                  color: Theme.of(
                    consumerContext,
                  ).colorScheme.onSurface.withAlpha(100),
                ),
                const SizedBox(height: 20),
                Text(
                  "No student profile found.",
                  style: TextStyle(
                    fontSize: 18,
                    color: Theme.of(
                      consumerContext,
                    ).colorScheme.onSurface.withAlpha(178),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  "Please add your profile using the '+' button in the Home tab.",
                  style: TextStyle(
                    fontSize: 16,
                    color: Theme.of(
                      consumerContext,
                    ).colorScheme.onSurface.withAlpha(178),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        final List<StudentSubject> studentEnrolledSubjects =
            studentSubjectsModel.subjects;

        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          "My Daily Attendance",
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(
                              consumerContext,
                            ).colorScheme.onSurface,
                          ),
                        ),
                        Text(
                          selectedStudent.registerNumber.isNotEmpty
                              ? 'Student: ${selectedStudent.name} (Reg. No: ${selectedStudent.registerNumber})'
                              : 'Student: ${selectedStudent.name} (No Register Number)',
                          style: TextStyle(
                            fontSize: 16,
                            color: Theme.of(
                              consumerContext,
                            ).colorScheme.onSurface.withAlpha(178),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 8.0,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(consumerContext).colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: Theme.of(consumerContext).brightness ==
                          Brightness.light
                      ? <BoxShadow>[
                          BoxShadow(
                            color: Colors.grey.withAlpha(25),
                            spreadRadius: 1,
                            blurRadius: 5,
                            offset: const Offset(0, 3),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  children: <Widget>[
                    Icon(
                      Icons.calendar_month,
                      color: Theme.of(consumerContext).colorScheme.primary,
                      size: 28,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        'Date: ${DateFormat('EEEE, MMM d, y').format(_selectedDate)}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Theme.of(
                            consumerContext,
                          ).colorScheme.onSurface,
                        ),
                      ),
                    ),
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Theme.of(consumerContext).brightness ==
                                Brightness.light
                            ? Colors.grey[200]
                            : Colors.grey[700],
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: Icon(
                          Icons.edit_calendar,
                          color: Theme.of(consumerContext).colorScheme.primary,
                        ),
                        onPressed: () => _selectDate(consumerContext),
                        tooltip: 'Change Attendance Date',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // New Card for General Attendance
              Card(
                margin: const EdgeInsets.symmetric(vertical: 4.0),
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8.0),
                ),
                color: _getCardColor(
                  attendanceData.getAttendance(
                    _selectedDate,
                    selectedStudent.registerNumber,
                    generalSubjectCode,
                  ),
                  Theme.of(consumerContext),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 8.0,
                  ),
                  leading: Icon(
                    Icons.check_circle_outline,
                    color: Theme.of(consumerContext).colorScheme.primary,
                  ),
                  title: Text(
                    "General Attendance",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(consumerContext).colorScheme.onSurface,
                    ),
                  ),
                  subtitle: Text(
                    'Status: ${_getStatusText(attendanceData.getAttendance(_selectedDate, selectedStudent.registerNumber, generalSubjectCode))}',
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(consumerContext)
                          .colorScheme
                          .onSurface
                          .withAlpha(178),
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      IconButton(
                        icon: Icon(
                          Icons.check_circle_outline,
                          color: Colors.green.shade500,
                        ),
                        onPressed: () {
                          attendanceData.setAttendance(
                            _selectedDate,
                            selectedStudent.registerNumber,
                            generalSubjectCode,
                            AttendanceStatus.present,
                          );
                          ScaffoldMessenger.of(consumerContext).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Marked General Attendance Present for ${DateFormat('MMM d').format(_selectedDate)}',
                              ),
                              duration: const Duration(seconds: 1, milliseconds: 500),
                            ),
                          );
                        },
                        tooltip: 'Mark Present',
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.cancel_outlined,
                          color: Colors.red.shade500,
                        ),
                        onPressed: () {
                          attendanceData.setAttendance(
                            _selectedDate,
                            selectedStudent.registerNumber,
                            generalSubjectCode,
                            AttendanceStatus.absent,
                          );
                          ScaffoldMessenger.of(consumerContext).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Marked General Attendance Absent for ${DateFormat('MMM d').format(_selectedDate)}',
                              ),
                              duration: const Duration(seconds: 1, milliseconds: 500),
                            ),
                          );
                        },
                        tooltip: 'Mark Absent',
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.adjust,
                          color: Colors.orange.shade500,
                        ),
                        onPressed: () {
                          attendanceData.setAttendance(
                            _selectedDate,
                            selectedStudent.registerNumber,
                            generalSubjectCode,
                            AttendanceStatus.halfday,
                          );
                          ScaffoldMessenger.of(consumerContext).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Marked General Attendance Half Day for ${DateFormat('MMM d').format(_selectedDate)}',
                              ),
                              duration: const Duration(seconds: 1, milliseconds: 500),
                            ),
                          );
                        },
                        tooltip: 'Mark Half Day',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                "Subject-Specific Attendance:",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(consumerContext).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              if (studentEnrolledSubjects.isEmpty)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Icon(
                          Icons.menu_book,
                          size: 60,
                          color: Theme.of(
                            consumerContext,
                          ).colorScheme.onSurface.withAlpha(100),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          "No subjects found for this student.",
                          style: TextStyle(
                            fontSize: 16,
                            color: Theme.of(
                              consumerContext,
                            ).colorScheme.onSurface.withAlpha(178),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          "Please add subjects in the 'Subjects' tab.",
                          style: TextStyle(
                            fontSize: 14,
                            color: Theme.of(
                              consumerContext,
                            ).colorScheme.onSurface.withAlpha(178),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.builder(
                    itemCount: studentEnrolledSubjects.length,
                    itemBuilder: (BuildContext listContext, int index) {
                      final StudentSubject subject =
                          studentEnrolledSubjects[index];
                      final AttendanceStatus currentStatus = attendanceData
                          .getAttendance(
                            _selectedDate,
                            selectedStudent.registerNumber,
                            subject.subjectCode,
                          );
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4.0),
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        color: _getCardColor(
                          currentStatus,
                          Theme.of(consumerContext),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16.0,
                            vertical: 8.0,
                          ),
                          leading: Icon(
                            Icons.class_,
                            color: Theme.of(
                              listContext,
                            ).colorScheme.primary,
                          ),
                          title: Text(
                            subject.name,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                              color: Theme.of(
                                listContext,
                              ).colorScheme.onSurface,
                            ),
                          ),
                          subtitle: Text(
                            'Code: ${subject.subjectCode.isNotEmpty ? subject.subjectCode : 'N/A'}\nStatus: ${_getStatusText(currentStatus)}',
                            style: TextStyle(
                              fontSize: 14,
                              color: Theme.of(
                                listContext,
                              ).colorScheme.onSurface.withAlpha(178),
                            ),
                          ),
                          // New trailing widget with attendance marking buttons
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              IconButton(
                                icon: Icon(
                                  Icons.check_circle_outline,
                                  color: Colors.green.shade500,
                                ),
                                onPressed: () {
                                  attendanceData.setAttendance(
                                    _selectedDate,
                                    selectedStudent.registerNumber,
                                    subject.subjectCode,
                                    AttendanceStatus.present,
                                  );
                                  ScaffoldMessenger.of(
                                    listContext,
                                  ).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Marked Present for ${subject.name} on ${DateFormat('MMM d').format(_selectedDate)}',
                                      ),
                                      duration: const Duration(seconds: 1, milliseconds: 500),
                                    ),
                                  );
                                },
                                tooltip: 'Mark Present',
                              ),
                              IconButton(
                                icon: Icon(
                                  Icons.cancel_outlined,
                                  color: Colors.red.shade500,
                                ),
                                onPressed: () {
                                  attendanceData.setAttendance(
                                    _selectedDate,
                                    selectedStudent.registerNumber,
                                    subject.subjectCode,
                                    AttendanceStatus.absent,
                                  );
                                  ScaffoldMessenger.of(
                                    listContext,
                                  ).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Marked Absent for ${subject.name} on ${DateFormat('MMM d').format(_selectedDate)}',
                                      ),
                                      duration: const Duration(seconds: 1, milliseconds: 500),
                                    ),
                                  );
                                },
                                tooltip: 'Mark Absent',
                              ),
                              IconButton(
                                icon: Icon(
                                  Icons.adjust, // Changed icon for Half Day
                                  color: Colors
                                      .orange
                                      .shade500, // Changed color for Half Day
                                ),
                                onPressed: () {
                                  attendanceData.setAttendance(
                                    _selectedDate,
                                    selectedStudent.registerNumber,
                                    subject.subjectCode,
                                    AttendanceStatus
                                        .halfday, // Changed to halfday
                                  );
                                  ScaffoldMessenger.of(
                                    listContext,
                                  ).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Marked Half Day for ${subject.name} on ${DateFormat('MMM d').format(_selectedDate)}', // Changed text
                                      ),
                                      duration: const Duration(seconds: 1, milliseconds: 500),
                                    ),
                                  );
                                },
                                tooltip: 'Mark Half Day', // Changed tooltip
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      consumerContext,
                      MaterialPageRoute<void>(
                        builder: (BuildContext context) =>
                            StudentAttendanceGraphPage(
                              student: selectedStudent,
                            ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.bar_chart),
                  label: const Text('View Historical Attendance Graph'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    textStyle: const TextStyle(fontSize: 18),
                    backgroundColor: Theme.of(
                      consumerContext,
                    ).colorScheme.primary,
                    foregroundColor: Theme.of(
                      consumerContext,
                    ).colorScheme.onPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Resolves a subject code to a display name using both student's and teacher's subject models.
/// This is a top-level function so it can be used by DataManagementUtils without a BuildContext.
String resolveSubjectNameForDisplay(
  String subjectCode,
  List<StudentSubject> studentSubjects,
  List<TeacherSubject> teacherSubjects,
) {
  if (subjectCode == 'GENERAL') {
    return 'General Attendance';
  }
  if (subjectCode.isEmpty) return 'Unnamed Class';

  // Check student's enrolled subjects first
  final StudentSubject? studentSub = studentSubjects.firstWhereOrNull(
    (StudentSubject s) => s.subjectCode == subjectCode,
  );
  if (studentSub != null) {
    if (studentSub.name.toLowerCase() == subjectCode.toLowerCase() ||
        studentSub.name.isEmpty) {
      return subjectCode;
    }
    return '${studentSub.name} ($subjectCode)';
  }

  // Then check teacher's subjects
  final TeacherSubject? teacherSub = teacherSubjects.firstWhereOrNull(
    (TeacherSubject s) => s.code == subjectCode,
  );
  if (teacherSub != null) {
    if (teacherSub.name.toLowerCase() == subjectCode.toLowerCase() ||
        teacherSub.name.isEmpty) {
      return subjectCode;
    }
    return '${teacherSub.name} ($subjectCode)';
  }

  // If not found in either, indicate it's an unlisted class
  return '$subjectCode (Unlisted Class)';
}

/// A custom widget to display individual attendance entries in a graph-like format.
class AttendanceGraphEntry extends StatelessWidget {
  final DateTime date;
  final AttendanceStatus status;
  final String subjectCode; // Added subjectCode to display
  final String subjectDisplayName; // New field for displaying subject name
  final double scaleFactor;
  final Color baseColor;

  const AttendanceGraphEntry({
    super.key,
    required this.date,
    required this.status,
    required this.subjectCode, // Made required
    required this.subjectDisplayName, // Made required
    this.scaleFactor = 1.0,
    required this.baseColor,
  });

  Color _getStatusColor(BuildContext context) {
    switch (status) {
      case AttendanceStatus.present:
        return Colors.green.shade500;
      case AttendanceStatus.absent:
        return Colors.red.shade500;
      case AttendanceStatus.halfday: // New case for Half Day
        return Colors.orange.shade500;
      case AttendanceStatus.noclass: // Previously unknown/halfday
        final Color onSurfaceColor = Theme.of(context).colorScheme.onSurface;
        return Color.fromARGB(
          (0.3 * 255.0).round(),
          // ignore: deprecated_member_use
          onSurfaceColor.red,
          // ignore: deprecated_member_use
          onSurfaceColor.green,
          // ignore: deprecated_member_use
          onSurfaceColor.blue,
        );
    }
  }

  String _getStatusText() {
    switch (status) {
      case AttendanceStatus.present:
        return 'Present';
      case AttendanceStatus.absent:
        return 'Absent';
      case AttendanceStatus.halfday: // New case for Half Day
        return 'Half Day';
      case AttendanceStatus.noclass:
        return 'No Class'; // Explicitly return for noclass
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color statusColor = _getStatusColor(context);
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      color: isDarkMode
          ? Theme.of(context).cardColor
          : statusColor.withAlpha(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: 6.0,
          horizontal: 10.0,
        ), // Reduced padding
        child: Row(
          children: <Widget>[
            Container(
              width: 8,
              height: 30, // Reduced height
              decoration: BoxDecoration(
                color: statusColor,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    DateFormat('EEEE, MMM d, y').format(date),
                    style: TextStyle(
                      fontSize: 14, // Reduced font size
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    'Subject: $subjectDisplayName - Status: ${_getStatusText()}', // Display subject name
                    style: TextStyle(
                      fontSize: 12, // Reduced font size
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withAlpha(178),
                    ),
                  ),
                ],
              ),
            ),
            Tooltip(
              message: _getStatusText(), // Tooltip for status icon
              child: Icon(
                _getIconForStatus(status),
                color: statusColor,
                size: 24, // Original was 2, which is too small
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getIconForStatus(AttendanceStatus status) {
    switch (status) {
      case AttendanceStatus.present:
        return Icons.check_circle;
      case AttendanceStatus.absent:
        return Icons.cancel;
      case AttendanceStatus.halfday:
        return Icons.adjust;
      case AttendanceStatus.noclass: // Previously halfday/unknown
        return Icons.event_busy; // Icon for 'No Class'
    }
  }
}

/// Represents an option in the subject selection dropdown.
class SubjectOption {
  final String displayName;
  final String? subjectCode; // null for "Overall Attendance"

  const SubjectOption({required this.displayName, this.subjectCode});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SubjectOption &&
          runtimeType == other.runtimeType &&
          displayName == other.displayName &&
          subjectCode == other.subjectCode;

  @override
  int get hashCode => Object.hash(displayName, subjectCode);
}

/// A new page to display a single student's attendance in a graph format.
class StudentAttendanceGraphPage extends StatefulWidget {
  final Student student;

  const StudentAttendanceGraphPage({super.key, required this.student});

  @override
  State<StudentAttendanceGraphPage> createState() =>
      _StudentAttendanceGraphPageState();
}

class _StudentAttendanceGraphPageState
    extends State<StudentAttendanceGraphPage> {
  // Use 'OVERALL' as a special code to denote overall attendance across all subjects.
  String? _selectedSubjectCode = 'OVERALL';

  /// Calculates the attendance percentage for a given student for a specific subject or overall.
  /// If [subjectCode] is 'OVERALL', it calculates overall attendance.
  /// Otherwise, it calculates attendance for the specified subject.
  /// This function includes attendance marked as "extra classes" if it's for the selected subject
  /// or part of the overall records, as all subject-specific attendance is stored uniformly.
  double _calculatePercentage(
    String studentRegisterNumber,
    String? subjectCode,
    AttendanceData attendanceData,
    bool isTeacher, // NEW parameter to filter for teacher-managed subjects
    List<TeacherSubject> teacherSubjects, // NEW parameter
  ) {
    double totalPresentDays = 0.0;
    int totalAttendanceDaysConsidered =
        0; // Days where class was held and attendance was marked present/absent/halfday

    if (subjectCode == 'OVERALL') {
      Map<DateTime, Map<String, AttendanceStatus>> studentOverallRecords;
      if (isTeacher) {
        studentOverallRecords = attendanceData
            .getStudentTeacherManagedAttendanceAcrossTeacherSubjects(
          studentRegisterNumber,
          teacherSubjects,
        );
      } else {
        studentOverallRecords = attendanceData
            .getStudentOverallAttendanceAcrossAllSubjects(
          studentRegisterNumber,
        );
      }

      if (studentOverallRecords.isEmpty) {
        return 0.0;
      }

      studentOverallRecords.forEach((
        DateTime date,
        Map<String, AttendanceStatus> subjectStatusMap,
      ) {
        subjectStatusMap.forEach((String sCode, AttendanceStatus status) {
          if (status != AttendanceStatus.noclass) {
            totalAttendanceDaysConsidered++;
            if (status == AttendanceStatus.present) {
              totalPresentDays += 1.0;
            } else if (status == AttendanceStatus.halfday) {
              totalPresentDays += 0.5;
            }
          }
        });
      });
    } else if (subjectCode != null) {
      // At this point, subjectCode is guaranteed not to be 'OVERALL' and not null.
      final Map<DateTime, AttendanceStatus> subjectRecords = attendanceData
          .getStudentAttendanceForSubject(studentRegisterNumber, subjectCode);
      if (subjectRecords.isEmpty) {
        return 0.0;
      }

      subjectRecords.forEach((DateTime date, AttendanceStatus status) {
        if (status != AttendanceStatus.noclass) {
          totalAttendanceDaysConsidered++;
          if (status == AttendanceStatus.present) {
            totalPresentDays += 1.0;
          } else if (status == AttendanceStatus.halfday) {
            totalPresentDays += 0.5;
          }
        }
      });
    }

    return totalAttendanceDaysConsidered == 0
        ? 0.0
        : (totalPresentDays / totalAttendanceDaysConsidered) * 100.0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historical Attendance'),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        foregroundColor: Theme.of(context).appBarTheme.foregroundColor,
        elevation: 4,
      ),
      body: provider_lib.Consumer<UserSession>(
        builder: (
          BuildContext userSessionContext,
          UserSession userSession,
          Widget? userSessionChild,
        ) {
          final bool isTeacher = userSession.userRole == UserRole.teacher;
          return Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      widget.student.name,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      widget.student.registerNumber.isNotEmpty
                          ? 'Register No: ${widget.student.registerNumber}'
                          : 'No Register Number',
                      style: TextStyle(
                        fontSize: 16,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withAlpha(178),
                      ),
                    ),
                    const SizedBox(height: 16),
                    provider_lib.Consumer2<StudentSubjectsModel,
                        TeacherSubjectsData>(
                      builder: (
                        BuildContext context,
                        StudentSubjectsModel studentSubjectsModel,
                        TeacherSubjectsData teacherSubjectsData,
                        Widget? child,
                      ) {
                        // Dynamically build subject options for the dropdown
                        final List<SubjectOption> availableSubjectOptions =
                            <SubjectOption>[
                          const SubjectOption(
                            displayName: 'Overall Attendance',
                            subjectCode: 'OVERALL',
                          ),
                          const SubjectOption(
                            displayName: 'General Attendance',
                            subjectCode: 'GENERAL',
                          ),
                        ];

                        final Set<String> allRelevantSubjectCodes = <String>{};
                        // For teachers, filter subjects based on their definitions.
                        // For students, consider their enrolled subjects and any recorded attendance.
                        if (isTeacher) {
                          allRelevantSubjectCodes.addAll(teacherSubjectsData
                              .subjects
                              .map((TeacherSubject s) => s.code));
                        } else {
                          allRelevantSubjectCodes.addAll(studentSubjectsModel
                              .subjects
                              .map((StudentSubject s) => s.subjectCode));
                        }

                        // Also consider any subject codes that have attendance records, regardless of if they're in student/teacher lists
                        // This ensures that "extra classes" or subjects not explicitly listed in current models are still visible.
                        final Map<DateTime, Map<String, AttendanceStatus>>
                            allStudentRecords = provider_lib.Provider.of<
                                AttendanceData>(
                          context,
                          listen: false,
                        ).getStudentOverallAttendanceAcrossAllSubjects(
                          widget.student.registerNumber,
                        );

                        allStudentRecords.forEach((
                          DateTime date,
                          Map<String, AttendanceStatus> subjectStatusMap,
                        ) {
                          subjectStatusMap.forEach((
                            String sCode,
                            AttendanceStatus status,
                          ) {
                            if (status != AttendanceStatus.noclass) {
                              // For teachers, only add codes that are either 'GENERAL' or explicitly defined by teacher
                              // For students, add all codes with attendance records
                              if (isTeacher) {
                                if (sCode == 'GENERAL' ||
                                    teacherSubjectsData.subjects.any(
                                        (TeacherSubject s) => s.code == sCode)) {
                                  allRelevantSubjectCodes.add(sCode);
                                }
                              } else {
                                allRelevantSubjectCodes.add(sCode);
                              }
                            }
                          });
                        });

                        allRelevantSubjectCodes
                            .remove('GENERAL'); // Already added explicitly

                        final List<String> sortedRelevantSubjectCodes =
                            allRelevantSubjectCodes.toList()..sort();

                        for (final String code in sortedRelevantSubjectCodes) {
                          final String displayName = resolveSubjectNameForDisplay(
                            code,
                            studentSubjectsModel.subjects,
                            teacherSubjectsData.subjects,
                          );

                          availableSubjectOptions.add(
                            SubjectOption(
                              displayName: displayName,
                              subjectCode: code,
                            ),
                          );
                        }

                        // Ensure _selectedSubjectCode is a valid option, or reset to 'OVERALL'
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted &&
                              !availableSubjectOptions.any(
                                (SubjectOption opt) =>
                                    opt.subjectCode == _selectedSubjectCode,
                              )) {
                            setState(() {
                              _selectedSubjectCode = availableSubjectOptions
                                  .first
                                  .subjectCode; // Default to 'Overall Attendance'
                            });
                          }
                        });

                        return DropdownButtonFormField<String>(
                          value: _selectedSubjectCode, // Changed from initialValue to value
                          decoration: InputDecoration(
                            labelText: 'View Attendance For:',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8.0),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8.0),
                              borderSide: BorderSide(
                                color: Theme.of(context).colorScheme.primary,
                                width: 2.0,
                              ),
                            ),
                            floatingLabelStyle: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16.0,
                              vertical: 8.0,
                            ),
                          ),
                          items: availableSubjectOptions
                              .map<DropdownMenuItem<String>>((
                                SubjectOption option,
                              ) {
                                return DropdownMenuItem<String>(
                                  value: option.subjectCode,
                                  child: Text(option.displayName),
                                );
                              })
                              .toList(),
                          onChanged: (String? newValue) {
                            if (newValue != null) {
                              setState(() {
                                _selectedSubjectCode = newValue;
                              });
                            }
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    provider_lib.Consumer3<AttendanceData,
                        StudentSubjectsModel, TeacherSubjectsData>(
                      builder: (
                        BuildContext context,
                        AttendanceData attendanceData,
                        StudentSubjectsModel studentSubjectsModel,
                        TeacherSubjectsData teacherSubjectsData,
                        Widget? child,
                      ) {
                        final double currentPercentage = _calculatePercentage(
                          widget.student.registerNumber,
                          _selectedSubjectCode,
                          attendanceData,
                          isTeacher, // Pass isTeacher
                          teacherSubjectsData.subjects, // Pass teacher's subjects
                        );

                        final List<Map<String, dynamic>> flatRecords;
                        if (_selectedSubjectCode == 'OVERALL') {
                          Map<DateTime, Map<String, AttendanceStatus>>
                              overallRecordsMap;
                          if (isTeacher) {
                            overallRecordsMap = attendanceData
                                .getStudentTeacherManagedAttendanceAcrossTeacherSubjects(
                              widget.student.registerNumber,
                              teacherSubjectsData.subjects,
                            );
                          } else {
                            overallRecordsMap = attendanceData
                                .getStudentOverallAttendanceAcrossAllSubjects(
                              widget.student.registerNumber,
                            );
                          }

                          flatRecords = overallRecordsMap.entries
                              .expand<Map<String, dynamic>>((
                                MapEntry<DateTime,
                                        Map<String, AttendanceStatus>>
                                    entry,
                              ) {
                                final DateTime date = entry.key;
                                final Map<String, AttendanceStatus>
                                    subjectStatusMap = entry.value;
                                return subjectStatusMap.entries.map<
                                    Map<String, dynamic>>((
                                  MapEntry<String, AttendanceStatus> subEntry,
                                ) {
                                  final String subjectCode = subEntry.key;
                                  final AttendanceStatus status = subEntry.value;
                                  final String subjectDisplayName =
                                      resolveSubjectNameForDisplay(
                                    subjectCode,
                                    studentSubjectsModel.subjects,
                                    teacherSubjectsData.subjects,
                                  );
                                  return <String, dynamic>{
                                    'date': date,
                                    'subjectCode': subjectCode,
                                    'status': status,
                                    'subjectDisplayName':
                                        subjectDisplayName, // ADDED
                                  };
                                });
                              })
                              .toList();
                        } else if (_selectedSubjectCode != null) {
                          final String actualSubjectCode =
                              _selectedSubjectCode!;
                          final Map<DateTime, AttendanceStatus> subjectRecords =
                              attendanceData.getStudentAttendanceForSubject(
                                widget.student.registerNumber,
                                actualSubjectCode,
                              );
                          final String subjectDisplayName =
                              resolveSubjectNameForDisplay(
                            actualSubjectCode,
                            studentSubjectsModel.subjects,
                            teacherSubjectsData.subjects,
                          );
                          flatRecords = subjectRecords.entries
                              .map<Map<String, dynamic>>((
                                MapEntry<DateTime, AttendanceStatus> entry,
                              ) {
                                final DateTime date = entry.key;
                                final AttendanceStatus status = entry.value;
                                return <String, dynamic>{
                                  'date': date,
                                  'subjectCode': actualSubjectCode,
                                  'status': status,
                                  'subjectDisplayName':
                                      subjectDisplayName, // ADDED
                                };
                              })
                              .toList();
                        } else {
                          // Fallback for when _selectedSubjectCode is null and not 'OVERALL'
                          flatRecords = <Map<String, dynamic>>[];
                        }

                        flatRecords.sort((
                          Map<String, dynamic> a,
                          Map<String, dynamic> b,
                        ) {
                          final int dateComparison = (a['date'] as DateTime)
                              .compareTo(b['date'] as DateTime);
                          if (dateComparison != 0) {
                            return dateComparison;
                          }
                          return (a['subjectCode'] as String).compareTo(
                            b['subjectCode'] as String,
                          );
                        });

                        // Filter out 'noclass' from the count if the user is looking at 'overall' or a specific subject.
                        final int totalMarkedInstances = flatRecords
                            .where(
                              (Map<String, dynamic> record) =>
                                  record['status'] != AttendanceStatus.noclass,
                            )
                            .length;

                        return Card(
                          elevation: 4,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              10,
                            ), // Slightly smaller radius
                            side: BorderSide(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withAlpha(50),
                              width: 1.5,
                            ), // Use onSurface for border
                          ),
                          child: Padding(
                            padding:
                                const EdgeInsets.all(10.0), // Reduced padding
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  'Current Selection Attendance Percentage:',
                                  style: TextStyle(
                                    fontSize: 14, // Reduced font size
                                    fontWeight: FontWeight.w500,
                                    color: Theme.of(context).colorScheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 4), // Reduced height
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: <Widget>[
                                    Expanded(
                                      child: ClipRRect(
                                        // Wrap LinearProgressIndicator with ClipRRect
                                        borderRadius: BorderRadius.circular(4),
                                        child: LinearProgressIndicator(
                                          value: currentPercentage / 100,
                                          backgroundColor: Theme.of(
                                            context,
                                          ).colorScheme.onSurface.withAlpha(50),
                                          color: currentPercentage >= 75
                                              ? Colors.green.shade500
                                              : currentPercentage >= 50
                                                  ? Colors.orange.shade500
                                                  : Colors.red.shade500,
                                          minHeight: 4, // Added for consistency
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8), // Reduced width
                                    Text(
                                      '${currentPercentage.toStringAsFixed(1)}%',
                                      style: TextStyle(
                                        fontSize: 16, // Reduced font size
                                        fontWeight: FontWeight.bold,
                                        color: currentPercentage >= 75
                                            ? Colors.green.shade500
                                            : currentPercentage >= 50
                                                ? Colors.orange.shade500
                                                : Colors.red.shade500,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4), // Reduced height
                                Text(
                                  'Total Classes Considered: $totalMarkedInstances',
                                  style: TextStyle(
                                    fontSize: 12, // Reduced font size
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface.withAlpha(178),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                    Text(
                      "Daily Attendance Breakdown:",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
              provider_lib.Consumer3<AttendanceData, StudentSubjectsModel,
                  TeacherSubjectsData>(
                builder: (
                  BuildContext context,
                  AttendanceData attendanceData,
                  StudentSubjectsModel studentSubjectsModel,
                  TeacherSubjectsData teacherSubjectsData,
                  Widget? child,
                ) {
                  final List<Map<String, dynamic>> flatRecords;

                  if (_selectedSubjectCode == 'OVERALL') {
                    Map<DateTime, Map<String, AttendanceStatus>>
                        overallRecordsMap;
                    if (isTeacher) {
                      overallRecordsMap = attendanceData
                          .getStudentTeacherManagedAttendanceAcrossTeacherSubjects(
                        widget.student.registerNumber,
                        teacherSubjectsData.subjects,
                      );
                    } else {
                      overallRecordsMap = attendanceData
                          .getStudentOverallAttendanceAcrossAllSubjects(
                        widget.student.registerNumber,
                      );
                    }

                    flatRecords = overallRecordsMap.entries
                        .expand<Map<String, dynamic>>((
                          MapEntry<DateTime, Map<String, AttendanceStatus>>
                              entry,
                        ) {
                          final DateTime date = entry.key;
                          final Map<String, AttendanceStatus> subjectStatusMap =
                              entry.value;
                          return subjectStatusMap.entries
                              .map<Map<String, dynamic>>((
                                MapEntry<String, AttendanceStatus> subEntry,
                              ) {
                                final String subjectCode = subEntry.key;
                                final AttendanceStatus status = subEntry.value;
                                final String subjectDisplayName =
                                    resolveSubjectNameForDisplay(
                                  subjectCode,
                                  studentSubjectsModel.subjects,
                                  teacherSubjectsData.subjects,
                                );
                                return <String, dynamic>{
                                  'date': date,
                                  'subjectCode': subjectCode,
                                  'status': status,
                                  'subjectDisplayName':
                                      subjectDisplayName, // ADDED
                                };
                              });
                        })
                        .toList();
                  } else if (_selectedSubjectCode != null) {
                    final String actualSubjectCode = _selectedSubjectCode!;
                    final Map<DateTime, AttendanceStatus> subjectRecords =
                        attendanceData.getStudentAttendanceForSubject(
                      widget.student.registerNumber,
                      actualSubjectCode,
                    );
                    final String subjectDisplayName = resolveSubjectNameForDisplay(
                      actualSubjectCode, studentSubjectsModel.subjects, teacherSubjectsData.subjects,
                    );
                    flatRecords = subjectRecords.entries
                        .map<Map<String, dynamic>>((
                          MapEntry<DateTime, AttendanceStatus> entry,
                        ) {
                          final DateTime date = entry.key;
                          final AttendanceStatus status = entry.value;
                          return <String, dynamic>{
                            'date': date,
                            'subjectCode': actualSubjectCode,
                            'status': status,
                            'subjectDisplayName': subjectDisplayName, // ADDED
                          };
                        })
                        .toList();
                  } else {
                    flatRecords = <Map<String, dynamic>>[];
                  }

                  flatRecords.sort((
                    Map<String, dynamic> a,
                    Map<String, dynamic> b,
                  ) {
                    final int dateComparison = (a['date'] as DateTime)
                        .compareTo(b['date'] as DateTime);
                    if (dateComparison != 0) {
                      return dateComparison;
                    }
                    return (a['subjectCode'] as String).compareTo(
                      b['subjectCode'] as String,
                    );
                  });

                  if (flatRecords.isEmpty) {
                    return Expanded(
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            Icon(
                              Icons.calendar_month,
                              size: 60,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withAlpha(100),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              "No attendance records found for this student for the selected option.",
                              style: TextStyle(
                                fontSize: 16,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withAlpha(178),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    );
                  } else {
                    return Expanded(
                      child: ListView.builder(
                        itemCount: flatRecords.length,
                        itemBuilder: (BuildContext listContext, int index) {
                          final Map<String, dynamic> entry = flatRecords[index];
                          return AttendanceGraphEntry(
                            date: entry['date'] as DateTime,
                            status: entry['status'] as AttendanceStatus,
                            subjectCode: entry['subjectCode'] as String,
                            subjectDisplayName:
                                entry['subjectDisplayName'] as String, // PASS NEW FIELD
                            baseColor: Theme.of(
                              listContext,
                            ).colorScheme.primary,
                          );
                        },
                      ),
                    );
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

enum TeacherMoreOptions { otherOptions }

/// DATA_MODEL
/// Represents a subject with a name and a code, for the Teacher's perspective.
class TeacherSubject {
  final String name;
  final String code;

  const TeacherSubject({
    required this.name,
    required this.code, // Made required
  });

  // For equality checks (e.g., in List.contains, List.remove)
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TeacherSubject &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          code == other.code;

  @override
  int get hashCode => Object.hash(name, code);

  // Convert TeacherSubject object to a JSON-compatible map
  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        'code': code,
      };

  // Create a TeacherSubject object from a JSON map
  factory TeacherSubject.fromJson(Map<String, dynamic> json) {
    return TeacherSubject(
      name: json['name'] as String,
      code:
          json['code'] as String? ??
          '', // Handle potential null from older versions or missing field
    );
  }
}

/// DATA_MODEL
/// Data model for managing subjects for a teacher.
/// This model uses SharedPreferences for persistence.
class TeacherSubjectsData extends ChangeNotifier {
  List<TeacherSubject> _subjects;

  late SharedPreferences _prefs;
  static const String _subjectsKey = 'teacherSubjects';

  TeacherSubjectsData({List<TeacherSubject>? initialSubjects})
      : _subjects = initialSubjects ?? <TeacherSubject>[] {
    _initPrefsAndLoadData();
  }

  Future<void> _initPrefsAndLoadData() async {
    _prefs = await SharedPreferences.getInstance();
    await _loadSubjects();
    if (_subjects.isEmpty) {
      _subjects.addAll(<TeacherSubject>[]);
      await _saveSubjects();
    }
    notifyListeners();
  }

  List<TeacherSubject> get subjects =>
      List<TeacherSubject>.unmodifiable(_subjects);

  void addSubject(String name, String code) {
    final String trimmedName = name.trim();
    final String trimmedCode = code.trim();
    if (trimmedName.isNotEmpty && trimmedCode.isNotEmpty) {
      // Both name and code are strictly required for adding
      final TeacherSubject newSubject = TeacherSubject(
        name: trimmedName,
        code: trimmedCode,
      );
      if (!_subjects.any(
        (TeacherSubject s) =>
            s.name == newSubject.name && s.code == newSubject.code,
      )) {
        _subjects.add(newSubject);
        _subjects.sort(
          (TeacherSubject a, TeacherSubject b) =>
              a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        ); // Sort alphabetically
        _saveSubjects();
        notifyListeners();
      } else {
        debugPrint(
          'TeacherSubject "$trimmedName" with code "$trimmedCode" already exists.',
        );
      }
    } else {
      debugPrint('Subject name and code cannot be empty.');
    }
  }

  void removeSubject(TeacherSubject subject) {
    if (_subjects.remove(subject)) {
      _saveSubjects();
      notifyListeners();
    }
  }

  Future<void> _saveSubjects() async {
    final List<Map<String, dynamic>> subjectsJson = _subjects
        .map<Map<String, dynamic>>((TeacherSubject s) => s.toJson())
        .toList();
    await _prefs.setString(_subjectsKey, jsonEncode(subjectsJson));
  }

  Future<void> _loadSubjects() async {
    final String? subjectsString = _prefs.getString(_subjectsKey);
    if (subjectsString != null) {
      try {
        final List<dynamic> subjectsJson =
            jsonDecode(subjectsString) as List<dynamic>;
        _subjects = subjectsJson
            .map<TeacherSubject>(
              (dynamic item) =>
                  TeacherSubject.fromJson(item as Map<String, dynamic>),
            )
            .toList();
        _subjects.sort(
          (TeacherSubject a, TeacherSubject b) =>
              a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        ); // Sort alphabetically on load
      } catch (e) {
        debugPrint(
          'Error loading teacher subjects: $e. Clearing corrupted data.',
        );
        _subjects.clear(); // Clear data if overall decoding or structure is bad
      }
    }
  }
}

/// DATA_MODEL
/// Enum to define the attendance status for a student on a specific date.
enum AttendanceStatus {
  present,
  absent,
  halfday, // NEW: represents half-day attendance, counts as 0.5
  noclass, // EXISTING: represents no class held or attendance not marked, counts as 0 days
}

/// DATA_MODEL
/// Data model for managing attendance records, now supporting subject-specific attendance.
/// This model persists attendance using SharedPreferences.
class AttendanceData extends ChangeNotifier {
  // Map: SubjectCode -> Date (YYYY-MM-DD) -> StudentRegisterNumber -> AttendanceStatus
  final Map<String, Map<DateTime, Map<String, AttendanceStatus>>>
      _attendanceRecords = <String, Map<DateTime, Map<String, AttendanceStatus>>>{};
  late SharedPreferences _prefs;
  static const String _attendanceKey =
      'attendanceRecordsV4'; // Changed key for new structure

  AttendanceData() {
    _initPrefsAndLoadData();
  }

  Future<void> _initPrefsAndLoadData() async {
    _prefs = await SharedPreferences.getInstance();
    await _loadAttendanceRecords();
    notifyListeners();
  }

  AttendanceStatus getAttendance(
    DateTime date,
    String studentRegisterNumber,
    String subjectCode,
  ) {
    final DateTime normalizedDate = DateUtils.dateOnly(date);
    return _attendanceRecords[subjectCode]?[normalizedDate]?[studentRegisterNumber] ??
        AttendanceStatus.noclass; // Default to noclass
  }

  void setAttendance(
    DateTime date,
    String studentRegisterNumber,
    String subjectCode,
    AttendanceStatus status,
  ) {
    final DateTime normalizedDate = DateUtils.dateOnly(date);

    _attendanceRecords
            .putIfAbsent(
              subjectCode,
              () => <DateTime, Map<String, AttendanceStatus>>{},
            )
            .putIfAbsent(
              normalizedDate,
              () => <String, AttendanceStatus>{},
            )[studentRegisterNumber] =
        status;

    // Note: Attendance marked for "extra classes" also uses the specific subjectCode
    // and is stored here like any other subject-specific attendance.
    // This ensures it is included in subject and overall attendance calculations.
    _saveAttendanceRecords();
    notifyListeners();
  }

  /// Returns all attendance records for a given student for a specific subject.
  /// The map key is the normalized date (YYYY-MM-DD).
  Map<DateTime, AttendanceStatus> getStudentAttendanceForSubject(
    String studentRegisterNumber,
    String subjectCode,
  ) {
    final Map<DateTime, AttendanceStatus> subjectRecords =
        <DateTime, AttendanceStatus>{};
    final Map<DateTime, Map<String, AttendanceStatus>>? subjectAttendance =
        _attendanceRecords[subjectCode];

    if (subjectAttendance != null) {
      subjectAttendance.forEach((
        DateTime date,
        Map<String, AttendanceStatus> studentStatusMap,
      ) {
        if (studentStatusMap.containsKey(studentRegisterNumber)) {
          subjectRecords[date] = studentStatusMap[studentRegisterNumber]!;
        }
      });
    }
    return subjectRecords;
  }

  /// Returns all attendance records for a given student across all subjects and all recorded dates.
  /// The outer map key is the normalized date (YYYY-MM-DD), inner map key is subjectCode.
  Map<DateTime, Map<String, AttendanceStatus>>
      getStudentOverallAttendanceAcrossAllSubjects(
          String studentRegisterNumber) {
    final Map<DateTime, Map<String, AttendanceStatus>> overallRecords =
        <DateTime, Map<String, AttendanceStatus>>{};

    _attendanceRecords.forEach((
      String subjectCode,
      Map<DateTime, Map<String, AttendanceStatus>> subjectDailyRecords,
    ) {
      subjectDailyRecords.forEach((
        DateTime date,
        Map<String, AttendanceStatus> studentStatusMap,
      ) {
        if (studentStatusMap.containsKey(studentRegisterNumber)) {
          overallRecords.putIfAbsent(
            date,
            () => <String, AttendanceStatus>{},
          )[subjectCode] = studentStatusMap[studentRegisterNumber]!;
        }
      });
    });
    return overallRecords;
  }

  /// NEW: Returns attendance records for a given student, filtered to include only 'GENERAL' and subjects managed by the teacher.
  Map<DateTime, Map<String, AttendanceStatus>>
      getStudentTeacherManagedAttendanceAcrossTeacherSubjects(
    String studentRegisterNumber,
    List<TeacherSubject> teacherSubjects,
  ) {
    final Map<DateTime, Map<String, AttendanceStatus>> filteredOverallRecords =
        <DateTime, Map<String, AttendanceStatus>>{};

    final Set<String> teacherManagedSubjectCodes =
        teacherSubjects.map<String>((TeacherSubject s) => s.code).toSet();
    teacherManagedSubjectCodes
        .add('GENERAL'); // Always include general attendance for teachers

    _attendanceRecords.forEach((
      String subjectCode,
      Map<DateTime, Map<String, AttendanceStatus>> subjectDailyRecords,
    ) {
      if (teacherManagedSubjectCodes.contains(
        subjectCode,
      )) {
        // Filter by teacher's subjects + general
        subjectDailyRecords.forEach((
          DateTime date,
          Map<String, AttendanceStatus> studentStatusMap,
        ) {
          if (studentStatusMap.containsKey(studentRegisterNumber)) {
            filteredOverallRecords.putIfAbsent(
              date,
              () => <String, AttendanceStatus>{},
            )[subjectCode] = studentStatusMap[studentRegisterNumber]!;
          }
        });
      }
    });
    return filteredOverallRecords;
  }

  /// NEW: Clears all attendance records associated with a specific student register number.
  Future<void> clearAttendanceForStudent(String studentRegisterNumber) async {
    bool changed = false;
    _attendanceRecords.forEach((
      String subjectCode,
      Map<DateTime, Map<String, AttendanceStatus>> subjectDailyRecords,
    ) {
      final List<DateTime> datesToRemove = <DateTime>[];
      subjectDailyRecords.forEach((
        DateTime date,
        Map<String, AttendanceStatus> studentStatusMap,
      ) {
        if (studentStatusMap.remove(studentRegisterNumber) != null) {
          changed = true;
        }
        if (studentStatusMap.isEmpty) {
          datesToRemove.add(date);
        }
      });
      for (final DateTime date in datesToRemove) {
        subjectDailyRecords.remove(date);
      }
    });

    // Remove any subject entries that became empty
    final List<String> subjectsToRemove = _attendanceRecords.entries
        .where(
          (
            MapEntry<String, Map<DateTime, Map<String, AttendanceStatus>>>
                entry,
          ) =>
              entry.value.isEmpty,
        )
        .map<String>(
          (
            MapEntry<String, Map<DateTime, Map<String, AttendanceStatus>>>
                entry,
          ) =>
              entry.key,
        )
        .toList();
    for (final String subjectCode in subjectsToRemove) {
      _attendanceRecords.remove(subjectCode);
      changed = true;
    }

    if (changed) {
      await _saveAttendanceRecords();
      notifyListeners();
    }
  }

  /// Returns a JSON-serializable map of all attendance records.
  Map<String, dynamic> get exportableRecords {
    final Map<String, dynamic> serializableMap = <String, dynamic>{};
    _attendanceRecords.forEach((
      String subjectCode,
      Map<DateTime, Map<String, AttendanceStatus>> subjectDailyRecords,
    ) {
      final Map<String, dynamic> serializableSubjectMap = <String, dynamic>{};
      subjectDailyRecords.forEach((
        DateTime date,
        Map<String, AttendanceStatus> studentStatusMap,
      ) {
        final String dateKey = date.toIso8601String().split(
          'T',
        )[0]; // YYYY-MM-DD
        final Map<String, String> serializableStudentStatus = studentStatusMap
            .map<String, String>(
              (String regNum, AttendanceStatus status) =>
                  MapEntry<String, String>(regNum, status.name),
            );
        serializableSubjectMap[dateKey] = serializableStudentStatus;
      });
      serializableMap[subjectCode] = serializableSubjectMap;
    });
    return serializableMap;
  }

  // Persistence methods
  Future<void> _saveAttendanceRecords() async {
    final Map<String, dynamic> serializableMap = exportableRecords;
    await _prefs.setString(_attendanceKey, jsonEncode(serializableMap));
    // debugPrint('Saved attendance records: ${jsonEncode(serializableMap)}'); // Too verbose
  }

  Future<void> _loadAttendanceRecords() async {
    final String? jsonString = _prefs.getString(_attendanceKey);
    if (jsonString != null && jsonString.isNotEmpty) {
      try {
        final Map<String, dynamic> decodedMap =
            jsonDecode(jsonString) as Map<String, dynamic>;
        _attendanceRecords.clear(); // Clear existing in-memory records

        decodedMap.forEach((String subjectCode, dynamic subjectDailyRecords) {
          if (subjectDailyRecords is! Map) {
            // Ensure subjectDailyRecords is a Map
            debugPrint(
              'Warning: Skipping malformed subjectDailyRecords for subject "$subjectCode". Expected a Map, got ${subjectDailyRecords.runtimeType}.',
            );
            return;
          }
          final Map<String, dynamic> innerSubjectMap =
              subjectDailyRecords as Map<String, dynamic>;

          final Map<DateTime, Map<String, AttendanceStatus>> attendanceByDate =
              <DateTime, Map<String, AttendanceStatus>>{};

          innerSubjectMap.forEach((String dateKey, dynamic studentStatusMap) {
            DateTime parsedDate;
            try {
              parsedDate = DateTime.parse(dateKey);
            } on FormatException catch (e) {
              debugPrint(
                'Warning: Failed to parse date string "$dateKey" into DateTime: $e. Skipping attendance entry.',
              );
              return;
            }

            if (studentStatusMap is! Map) {
              // Ensure studentStatusMap is a Map
              debugPrint(
                'Warning: Skipping malformed studentStatusMap for date "$dateKey". Expected a Map, got ${studentStatusMap.runtimeType}.',
              );
              return;
            }
            final Map<String, dynamic> innerStudentMap =
                studentStatusMap as Map<String, dynamic>;

            final Map<String, AttendanceStatus> attendanceByStudent =
                <String, AttendanceStatus>{};
            innerStudentMap.forEach((String regNum, dynamic statusName) {
              if (statusName is! String) {
                debugPrint(
                  'Warning: Skipping malformed attendance status for student "$regNum" on date "$dateKey". Expected String, got ${statusName.runtimeType}.',
                );
                attendanceByStudent[regNum] =
                    AttendanceStatus.noclass; // Use noclass as fallback
                return;
              }
              attendanceByStudent[regNum] = AttendanceStatus.values.firstWhere(
                (AttendanceStatus e) => e.name == statusName,
                orElse: () => AttendanceStatus.noclass, // Default to noclass
              );
            });
            attendanceByDate[parsedDate] = attendanceByStudent;
          });
          _attendanceRecords[subjectCode] = attendanceByDate;
        });
      } catch (e) {
        debugPrint(
          'Major error loading attendance records from SharedPreferences, data might be corrupted: $e. Clearing all attendance data.',
        );
        _attendanceRecords
            .clear(); // Clear all data if overall decoding or structure is bad
        // Re-save empty records to ensure persistence is clean for next launch
        await _saveAttendanceRecords();
      }
    }
  }
}

/// A new page for the Teachers section, now with internal navigation.
class TeachersPage extends StatefulWidget {
  const TeachersPage({super.key});

  @override
  State<TeachersPage> createState() => _TeachersPageState();
}

class _TeachersPageState extends State<TeachersPage>
    with TickerProviderStateMixin {
  int _selectedIndex = 0;
  late final PageController _pageController;

  late final List<Widget> _teacherPages;

  final List<String> _pageTitles = <String>[
    "Teacher Home", // Renamed for clarity
    "Students",
    "Subjects",
    "Attendance (General)", // Clarified title
    "Settings",
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _selectedIndex);
    _teacherPages = const <Widget>[
      TeacherHomePage(),
      TeacherStudentPage(),
      TeacherSubjectsPage(),
      TeacherAttendancePage(),
      TeacherSettingsPage(),
    ];
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.ease,
    );
  }

  void _showAddStudentDialog(BuildContext contextForProvider) {
    final TextEditingController studentNameController = TextEditingController();
    final TextEditingController registerNumberController =
        TextEditingController();

    showDialog<void>(
      context: contextForProvider,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Add New Student'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(
                  controller: studentNameController,
                  decoration: InputDecoration(
                    labelText: 'Student Name *', // Added asterisk for required
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.0),
                      borderSide: BorderSide(
                        color: Theme.of(contextForProvider).colorScheme.primary,
                        width: 2.0,
                      ),
                    ),
                    floatingLabelStyle: TextStyle(
                      color: Theme.of(contextForProvider).colorScheme.primary,
                    ),
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: registerNumberController,
                  decoration: InputDecoration(
                    labelText: 'Register Number *', // Made required
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.0),
                      borderSide: BorderSide(
                        color: Theme.of(contextForProvider).colorScheme.primary,
                        width: 2.0,
                      ),
                    ),
                    floatingLabelStyle: TextStyle(
                      color: Theme.of(contextForProvider).colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                studentNameController.dispose();
                registerNumberController.dispose();
                Navigator.pop(dialogContext);
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final String newStudentName = studentNameController.text.trim();
                final String newRegisterNumber =
                    registerNumberController.text.trim();

                if (newStudentName.isEmpty) {
                  ScaffoldMessenger.of(contextForProvider).showSnackBar(
                    const SnackBar(
                      content: Text('Student name cannot be empty.'),
                      duration: Duration(seconds: 1, milliseconds: 500),
                    ),
                  );
                  return; // Stop here if name is empty
                }

                if (newRegisterNumber.isEmpty) {
                  ScaffoldMessenger.of(contextForProvider).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Register Number cannot be empty.', // Register number is now required
                      ),
                      duration: Duration(seconds: 1, milliseconds: 500),
                    ),
                  );
                  return; // Stop here if register number is empty
                }

                final StudentData studentData =
                    provider_lib.Provider.of<StudentData>(
                  contextForProvider,
                  listen: false,
                );
                final Student newStudent = Student(
                  name: newStudentName,
                  registerNumber: newRegisterNumber,
                );

                if (!studentData.students.any(
                  (Student s) =>
                      s.name == newStudent.name &&
                      s.registerNumber == newStudent.registerNumber,
                )) {
                  studentData.addStudent(newStudentName, newRegisterNumber);
                  Navigator.pop(dialogContext);
                  ScaffoldMessenger.of(contextForProvider).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Student "$newStudentName" (Reg. No: $newRegisterNumber) added!',
                      ),
                      duration: const Duration(
                        seconds: 1,
                        milliseconds: 500,
                      ), // Reduced duration
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(contextForProvider).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Student "$newStudentName" with register number "$newRegisterNumber" already exists.',
                      ),
                      duration: const Duration(
                        seconds: 1,
                        milliseconds: 500,
                      ), // Reduced duration
                    ),
                  );
                }
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    ).then((_) {
      studentNameController.dispose();
      registerNumberController.dispose();
    });
  }

  void _showAddSubjectDialog(BuildContext contextForProvider) {
    final TextEditingController subjectNameController = TextEditingController();
    final TextEditingController subjectCodeController = TextEditingController();

    showDialog<void>(
      context: contextForProvider,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Add New Subject'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(
                  controller: subjectNameController,
                  decoration: InputDecoration(
                    labelText: 'Subject Name *', // Added asterisk for required
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.0),
                      borderSide: BorderSide(
                        color: Theme.of(contextForProvider).colorScheme.primary,
                        width: 2.0,
                      ),
                    ),
                    floatingLabelStyle: TextStyle(
                      color: Theme.of(contextForProvider).colorScheme.primary,
                    ),
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: subjectCodeController,
                  decoration: InputDecoration(
                    labelText: 'Subject Code *', // Now required
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.0),
                      borderSide: BorderSide(
                        color: Theme.of(contextForProvider).colorScheme.primary,
                        width: 2.0,
                      ),
                    ),
                    floatingLabelStyle: TextStyle(
                      color: Theme.of(contextForProvider).colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                subjectNameController.dispose();
                subjectCodeController.dispose();
                Navigator.pop(dialogContext);
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final String newSubjectName = subjectNameController.text.trim();
                final String newSubjectCode = subjectCodeController.text.trim();

                if (newSubjectName.isEmpty) {
                  ScaffoldMessenger.of(contextForProvider).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Subject name cannot be empty.',
                      ),
                      duration: Duration(seconds: 1, milliseconds: 500), // Reduced duration
                    ),
                  );
                  return; // Stop here if name is empty
                }

                if (newSubjectCode.isEmpty) {
                  ScaffoldMessenger.of(contextForProvider).showSnackBar(
                    const SnackBar(
                      content: Text('Subject code cannot be empty.'),
                      duration: Duration(seconds: 1, milliseconds: 500),
                    ),
                  );
                  return; // Stop here if code is empty
                }

                final TeacherSubjectsData subjectsData =
                    provider_lib.Provider.of<TeacherSubjectsData>(
                  contextForProvider,
                  listen: false,
                );
                subjectsData.addSubject(newSubjectName, newSubjectCode);
                Navigator.pop(dialogContext);
                ScaffoldMessenger.of(contextForProvider).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Subject "$newSubjectName" (Code: $newSubjectCode) added!',
                    ),
                    duration: const Duration(
                      seconds: 1,
                      milliseconds: 500,
                    ), // Reduced duration
                  ),
                );
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    ).then((_) {
      subjectNameController.dispose();
      subjectCodeController.dispose();
    });
  }

  void _showSuggestFeatureDialog() {
    final TextEditingController suggestionController = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Suggest a Feature'),
          content: TextField(
            controller: suggestionController,
            decoration: InputDecoration(
              labelText: 'Your Suggestion',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8.0),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8.0),
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2.0,
                ),
              ),
              floatingLabelStyle: TextStyle(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            autofocus: true,
            maxLines: 3,
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                suggestionController.dispose();
                Navigator.pop(dialogContext);
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final String suggestion = suggestionController.text.trim();
                if (suggestion.isNotEmpty) {
                  debugPrint('User suggested feature: $suggestion');
                  Navigator.pop(dialogContext);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Thank you for your suggestion: "$suggestion"!',
                      ),
                      duration: const Duration(
                        seconds: 1,
                        milliseconds: 500,
                      ), // Reduced duration
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Suggestion cannot be empty.'),
                      duration: Duration(seconds: 1, milliseconds: 500), // Reduced duration
                    ),
                  );
                }
              },
              child: const Text('Submit'),
            ),
          ],
        );
      },
    ).then((_) {
      suggestionController.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _pageTitles[_selectedIndex],
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        foregroundColor: Theme.of(context).appBarTheme.foregroundColor,
        elevation: 4,
        actions: <Widget>[
          if (_selectedIndex != 0) // Only show date picker for non-home pages
            IconButton(
              icon: Icon(
                Icons.calendar_today,
                color: Theme.of(context).appBarTheme.foregroundColor,
              ),
              onPressed: () async {
                final DateTime? pickedDate = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now(),
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2101),
                  helpText: 'Select a Date',
                  cancelText: 'Cancel',
                  confirmText: 'Select',
                );

                if (pickedDate != null) {
                  final String formattedDate = DateFormat(
                    'EEEE, MMMM d, y',
                  ).format(pickedDate);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Date Selected: $formattedDate'),
                      duration: const Duration(
                        seconds: 1,
                        milliseconds: 500,
                      ), // Reduced duration
                    ),
                  );
                }
              },
            ),
          PopupMenuButton<TeacherMoreOptions>(
            icon: Icon(
              Icons.more_vert,
              color: Theme.of(context).appBarTheme.foregroundColor,
            ),
            onSelected: (TeacherMoreOptions result) {
              if (result == TeacherMoreOptions.otherOptions) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('More teacher options coming soon!'),
                    duration: Duration(seconds: 1, milliseconds: 500), // Reduced duration
                  ),
                );
              }
            },
            itemBuilder: (BuildContext context) =>
                <PopupMenuEntry<TeacherMoreOptions>>[
                  const PopupMenuItem<TeacherMoreOptions>(
                    value: TeacherMoreOptions.otherOptions,
                    child: Text('Other Options'),
                  ),
                ],
          ),
          if (_selectedIndex == 4) // This is the settings tab for teachers
            IconButton(
              icon: Icon(
                Icons.share,
                color: Theme.of(context).appBarTheme.foregroundColor,
              ),
              onPressed: () {
                final AppSettings appSettings = provider_lib
                    .Provider.of<AppSettings>(context, listen: false);
                ShareUtils.showAppShareOptionsDialog(
                  context,
                  appSettings,
                ); // Using the new helper
              },
            ),
        ],
      ),
      body: PageView(
        controller: _pageController,
        onPageChanged: (int index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        children: _teacherPages,
      ),
      floatingActionButton:
          (_selectedIndex == 1 || _selectedIndex == 2 || _selectedIndex == 4)
              ? FloatingActionButton(
                  heroTag: 'addFab',
                  onPressed: () {
                    if (_selectedIndex == 1) {
                      _showAddStudentDialog(context);
                    } else if (_selectedIndex == 2) {
                      _showAddSubjectDialog(context);
                    } else if (_selectedIndex == 4) {
                      _showSuggestFeatureDialog();
                    }
                  },
                  backgroundColor: Theme.of(context).colorScheme.secondary,
                  tooltip: _selectedIndex == 1
                      ? 'Add New Student'
                      : _selectedIndex == 2
                          ? 'Add New Subject'
                          : 'Suggest New Feature',
                  child: const Icon(Icons.add),
                )
              : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.people), label: 'Students'),
          BottomNavigationBarItem(icon: Icon(Icons.book), label: 'Subjects'),
          BottomNavigationBarItem(
            icon: Icon(Icons.check_box),
            label: 'Attendance',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Theme.of(context).colorScheme.primary,
        unselectedItemColor: Colors.grey,
        onTap: _onItemTapped,
        type: BottomNavigationBarType.fixed,
        backgroundColor: Theme.of(context).colorScheme.surface,
      ),
    );
  }
}

/// New placeholder page for Teacher Home.
class TeacherHomePage extends StatelessWidget {
  const TeacherHomePage({super.key});

  // Displays today's absent students in a dialog
  void _showTodaysAbsentStudents(BuildContext context) {
    final AttendanceData attendanceData =
        provider_lib.Provider.of<AttendanceData>(context, listen: false);
    final StudentData studentData = provider_lib.Provider.of<StudentData>(
      context,
      listen: false,
    );
    final DateTime today = DateUtils.dateOnly(DateTime.now());

    final List<Student> absentStudents = <Student>[];
    const String generalSubjectCode =
        'GENERAL'; // Consistent with TeacherAttendancePage

    for (final Student student in studentData.students) {
      final AttendanceStatus generalAttendanceStatus = attendanceData
          .getAttendance(
        today,
        student.registerNumber,
        generalSubjectCode,
      );

      if (generalAttendanceStatus == AttendanceStatus.absent) {
        absentStudents.add(student);
      }
    }

    // Sort absent students using the same logic as StudentData
    absentStudents.sort((Student a, Student b) {
      final bool aHasRegNum = a.registerNumber.isNotEmpty;
      final bool bHasRegNum = b.registerNumber.isNotEmpty;

      if (!aHasRegNum && !bHasRegNum) {
        // Both empty or neither has reg num, sort by name
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      }
      if (!aHasRegNum) return 1; // Empty reg num comes after non-empty
      if (!bHasRegNum) return -1; // Non-empty reg num comes before empty

      // Both have register numbers, attempt numeric comparison
      final int? aNum = int.tryParse(a.registerNumber);
      final int? bNum = int.tryParse(b.registerNumber);

      if (aNum != null && bNum != null) {
        // Both are pure numbers, compare numerically
        return aNum.compareTo(bNum);
      } else if (aNum != null) {
        return -1; // Numeric before alpha-numeric
      } else if (bNum != null) {
        return 1; // Alpha-numeric after numeric
      } else {
        // Both are non-numeric strings, sort lexicographically
        return a.registerNumber
            .toLowerCase()
            .compareTo(b.registerNumber.toLowerCase());
      }
    });

    String reportTitle =
        "Today's Absent Students (${DateFormat('MMM d, y').format(today)}) for Parents";
    String reportContent;

    if (absentStudents.isEmpty) {
      reportContent =
          "Dear Parents,\n\nOn ${DateFormat('EEEE, MMMM d, y').format(today)}, all students are marked present for general attendance! Keep up the good work!\n\nRegards,\nYour School/Teacher";
    } else {
      absentStudents.sort(
        (Student a, Student b) =>
            a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      final StringBuffer buffer = StringBuffer();
      buffer.writeln("Dear Parents,");
      buffer.writeln(
        "\nThis is an attendance report for ${DateFormat('EEEE, MMMM d, y').format(today)}.",
      );
      buffer.writeln(
          "\nThe following students are marked absent for general attendance:");
      for (int i = 0; i < absentStudents.length; i++) {
        final Student student = absentStudents[i];
        buffer.writeln(
          '${i + 1}. ${student.name} (Reg. No: ${student.registerNumber.isNotEmpty ? student.registerNumber : 'N/A'})',
        );
      }
      buffer.writeln(
        "\nPlease ensure your child's attendance and communicate any reasons for absence.",
      );
      buffer.writeln("\nRegards,\nYour School/Teacher");
      reportContent = buffer.toString();
    }

    ShareUtils.showGenericShareDialog(context, reportTitle, reportContent);
  }

  @override
  Widget build(BuildContext context) {
    return provider_lib.Consumer2<StudentData, TeacherSubjectsData>(
      builder: (
        BuildContext context,
        StudentData studentData,
        TeacherSubjectsData teacherSubjectsData,
        Widget? child,
      ) {
        final int totalStudents = studentData.students.length;
        final int totalSubjects = teacherSubjectsData.subjects.length;

        return Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(
                  Icons.home,
                  size: 80,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 20),
                Text(
                  "Teacher Home Overview",
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  "Your personalized home screen.",
                  style: TextStyle(
                    fontSize: 16,
                    color: Theme.of(context).colorScheme.onSurface.withAlpha(178),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 30),
                // Quick Stats Cards
                IntrinsicHeight(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: <Widget>[
                      Expanded(
                        child: Card(
                          elevation: 4,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              children: <Widget>[
                                Icon(Icons.people,
                                    size: 36,
                                    color: Theme.of(context).colorScheme.secondary),
                                const SizedBox(height: 8),
                                Text(
                                  'Total Students',
                                  style: TextStyle(
                                      fontSize: 14,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withAlpha(178)),
                                ),
                                Text(
                                  '$totalStudents',
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color:
                                        Theme.of(context).colorScheme.onSurface,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Card(
                          elevation: 4,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              children: <Widget>[
                                Icon(Icons.book,
                                    size: 36,
                                    color: Theme.of(context).colorScheme.primary),
                                const SizedBox(height: 8),
                                Text(
                                  'Total Subjects',
                                  style: TextStyle(
                                      fontSize: 14,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withAlpha(178)),
                                ),
                                Text(
                                  '$totalSubjects',
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color:
                                        Theme.of(context).colorScheme.onSurface,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (BuildContext context) =>
                            const TeacherStudentOverallAttendancePage(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.bar_chart),
                  label: const Text('View Overall Attendance Summary'),
                  style: ElevatedButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                    textStyle: const TextStyle(fontSize: 18),
                    backgroundColor: Theme.of(context).colorScheme.secondary,
                    foregroundColor: Theme.of(context).colorScheme.onSecondary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                // New button for Today's Absent Students
                ElevatedButton.icon(
                  onPressed: () => _showTodaysAbsentStudents(context),
                  icon: const Icon(Icons.group_off), // Corrected icon
                  label: const Text("Today's Absent Students"),
                  style: ElevatedButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                    textStyle: const TextStyle(fontSize: 18),
                    backgroundColor: Theme.of(context).colorScheme.error,
                    foregroundColor: Theme.of(context).colorScheme.onError,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// New page for Teacher Student Management, allowing adding and viewing students.
class TeacherStudentPage extends StatefulWidget {
  const TeacherStudentPage({super.key});

  @override
  State<TeacherStudentPage> createState() => _TeacherStudentPageState();
}

class _TeacherStudentPageState extends State<TeacherStudentPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchText = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _confirmRemoveStudent(Student student) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Confirm Deletion'),
          content: Text(
            'Are you sure you want to remove "${student.name}"${student.registerNumber.isNotEmpty ? ' (Reg. No: ${student.registerNumber})' : ''}?\n\nThis will also delete ALL their attendance records.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      final StudentData studentData = provider_lib.Provider.of<StudentData>(
        context,
        listen: false,
      );
      final AttendanceData attendanceData =
          provider_lib.Provider.of<AttendanceData>(context, listen: false);
      studentData.removeStudent(student);
      await attendanceData.clearAttendanceForStudent(
        student.registerNumber,
      ); // Clear attendance
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Student "${student.name}" removed.'),
          duration: const Duration(seconds: 1, milliseconds: 500), // Reduced duration
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return provider_lib.Consumer<StudentData>(
      builder: (BuildContext context, StudentData studentData, Widget? child) {
        final List<Student> filteredStudents = studentData.students.where((
          Student student,
        ) {
          final String lowerCaseSearchText = _searchText.toLowerCase();
          return student.name.toLowerCase().contains(lowerCaseSearchText) ||
              student.registerNumber.toLowerCase().contains(
                    lowerCaseSearchText,
                  );
        }).toList();

        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                "Your Students",
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 16),
              // Search Bar
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    labelText: 'Search Students by Name or Register No.',
                    hintText: 'Type to search...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchText.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _searchText = '';
                              });
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                    floatingLabelStyle: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.0),
                      borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.primary,
                        width: 2.0,
                      ),
                    ),
                  ),
                  onChanged: (String value) {
                    setState(() {
                      _searchText = value;
                    });
                  },
                ),
              ),
              const SizedBox(height: 10),
              if (studentData.students.isEmpty)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Icon(
                          Icons.person_off,
                          size: 60,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withAlpha(100),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          "No students added yet. Tap the '+' button to add one!",
                          style: TextStyle(
                            fontSize: 16,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withAlpha(178),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              else if (filteredStudents.isEmpty && _searchText.isNotEmpty)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Icon(
                          Icons.search_off,
                          size: 60,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withAlpha(100),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          "No results found for '$_searchText'.",
                          style: TextStyle(
                            fontSize: 16,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withAlpha(178),
                          ),
                            textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.builder(
                    itemCount: filteredStudents.length,
                    itemBuilder: (BuildContext listContext, int index) {
                      final Student student = filteredStudents[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4.0),
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16.0,
                            vertical: 8.0,
                          ),
                          leading: Icon(
                            Icons.person,
                            color: Theme.of(context).colorScheme.secondary,
                          ),
                          title: Text(
                            student.name,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          subtitle: Text(
                            student.registerNumber.isNotEmpty
                                ? 'Reg. No: ${student.registerNumber}'
                                : 'No Register Number',
                            style: TextStyle(
                              fontSize: 14,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withAlpha(178),
                            ),
                          ),
                          trailing: IconButton(
                            icon: Icon(
                              Icons.delete,
                              color: Theme.of(context).colorScheme.error,
                            ),
                            onPressed: () => _confirmRemoveStudent(student),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Page for Teacher Subjects, allowing adding and viewing subjects.
class TeacherSubjectsPage extends StatefulWidget {
  const TeacherSubjectsPage({super.key});

  @override
  State<TeacherSubjectsPage> createState() => _TeacherSubjectsPageState();
}

class _TeacherSubjectsPageState extends State<TeacherSubjectsPage> {
  Future<void> _confirmRemoveSubject(TeacherSubject subject) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Confirm Deletion'),
          content: Text(
            'Are you sure you want to remove "${subject.name}" (Code: ${subject.code})?',
          ), // Subject code is now guaranteed to be present
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      final TeacherSubjectsData subjectsData =
          provider_lib.Provider.of<TeacherSubjectsData>(context, listen: false);
      subjectsData.removeSubject(subject);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Subject "${subject.name}" removed.'),
          duration: const Duration(seconds: 1, milliseconds: 500), // Reduced duration
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return provider_lib.Consumer<TeacherSubjectsData>(
      builder: (
        BuildContext context,
        TeacherSubjectsData subjectsData,
        Widget? child,
      ) {
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                "Your Assigned Subjects",
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 16),
              if (subjectsData.subjects.isEmpty)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Icon(
                          Icons.inbox,
                          size: 60,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withAlpha(100),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          "No subjects added yet. Tap the '+' button to add one!",
                          style: TextStyle(
                            fontSize: 16,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withAlpha(178),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.builder(
                    itemCount: subjectsData.subjects.length,
                    itemBuilder: (BuildContext listContext, int index) {
                      final TeacherSubject subject =
                          subjectsData.subjects[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4.0),
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16.0,
                            vertical: 8.0,
                          ),
                          leading: Icon(
                            Icons.book_outlined,
                            color: Theme.of(
                              listContext,
                            ).colorScheme.secondary,
                          ),
                          title: Text(
                            subject.name,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                              color: Theme.of(
                                listContext,
                              ).colorScheme.onSurface,
                            ),
                          ),
                          subtitle: Text(
                            'Code: ${subject.code}', // Now guaranteed to have a code
                            style: TextStyle(
                              fontSize: 14,
                              color: Theme.of(
                                listContext,
                              ).colorScheme.onSurface.withAlpha(178),
                            ),
                          ),
                          trailing: IconButton(
                            icon: Icon(
                              Icons.delete,
                              color: Theme.of(context).colorScheme.error,
                            ),
                            onPressed: () => _confirmRemoveSubject(subject),
                          ),
                          onTap: () {
                            Navigator.push(
                              listContext,
                              MaterialPageRoute<void>(
                                builder: (BuildContext context) =>
                                    MarkSubjectAttendancePage(
                                      subject: subject,
                                    ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// A new page for marking attendance for a specific subject.
class MarkSubjectAttendancePage extends StatefulWidget {
  final TeacherSubject subject;
  const MarkSubjectAttendancePage({super.key, required this.subject});

  @override
  State<MarkSubjectAttendancePage> createState() =>
      _MarkSubjectAttendancePageState();
}

class _MarkSubjectAttendancePageState extends State<MarkSubjectAttendancePage> {
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _selectedDate = DateUtils.dateOnly(DateTime.now()); // Ensure date only
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
      helpText: 'Select Attendance Date',
      cancelText: 'Cancel',
      confirmText: 'Select',
      builder: (BuildContext context, Widget? child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: ColorScheme.light(
              primary: Theme.of(context).colorScheme.primary,
              onPrimary: Theme.of(context).colorScheme.onPrimary,
              surface: Theme.of(context).colorScheme.surface,
              onSurface: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && DateUtils.dateOnly(picked) != _selectedDate) {
      setState(() {
        _selectedDate = DateUtils.dateOnly(picked);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Attendance date set to: ${DateFormat('EEEE, MMMM d, y').format(_selectedDate)}',
          ),
          duration: const Duration(seconds: 1, milliseconds: 500), // Reduced duration
        ),
      );
    }
  }

  Color _getCardColor(AttendanceStatus status, ThemeData theme) {
    switch (status) {
      case AttendanceStatus.present:
        return Colors.green.shade500.withAlpha(51);
      case AttendanceStatus.absent:
        return Colors.red.shade500.withAlpha(26);
      case AttendanceStatus.halfday: // New case for Half Day
        return Colors.orange.shade300.withAlpha(51);
      case AttendanceStatus.noclass: // Previously halfday/unknown
        return theme.cardColor;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Mark Attendance for ${widget.subject.name}'),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        foregroundColor: Theme.of(context).appBarTheme.foregroundColor,
        elevation: 4,
      ),
      body: provider_lib.Consumer2<StudentData, AttendanceData>(
        builder: (
          BuildContext context,
          StudentData studentData,
          AttendanceData attendanceData,
          Widget? child,
        ) {
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  "Students for ${widget.subject.code}", // Now guaranteed to have a code
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 8.0,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow:
                        Theme.of(context).brightness == Brightness.light
                            ? <BoxShadow>[
                                BoxShadow(
                                  color: Colors.grey.withAlpha(25),
                                  spreadRadius: 1,
                                  blurRadius: 5,
                                  offset: const Offset(0, 3),
                                ),
                              ]
                            : null,
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        Icons.calendar_month,
                        color: Theme.of(context).colorScheme.primary,
                        size: 28,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          'Date: ${DateFormat('EEEE, MMM d, y').format(_selectedDate)}',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Theme.of(context).brightness == Brightness.light
                              ? Colors.grey[200]
                              : Colors.grey[700],
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          icon: Icon(
                            Icons.edit_calendar,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          onPressed: () => _selectDate(context),
                          tooltip: 'Change Attendance Date',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (studentData.students.isEmpty)
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          Icon(
                            Icons.group_off,
                            size: 60,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withAlpha(100),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            "No students added yet. Please add students in the 'Students' tab.",
                            style: TextStyle(
                              fontSize: 16,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withAlpha(178),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: ListView.builder(
                      itemCount: studentData.students.length,
                      itemBuilder: (BuildContext listContext, int index) {
                        final Student student = studentData.students[index];
                        final AttendanceStatus currentStatus =
                            attendanceData.getAttendance(
                                  _selectedDate,
                                  student.registerNumber,
                                  widget.subject.code,
                                );
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4.0),
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8.0),
                          ),
                          color: _getCardColor(
                            currentStatus,
                            Theme.of(context),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16.0,
                              vertical: 8.0,
                            ),
                            leading: Icon(
                              Icons.person_outline,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            title: Text(
                              student.name,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w500,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface,
                              ),
                            ),
                            subtitle: Text(
                              student.registerNumber.isNotEmpty
                                  ? 'Reg. No: ${student.registerNumber}'
                                  : 'No Register Number',
                              style: TextStyle(
                                fontSize: 14,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withAlpha(178),
                              ),
                            ),
                            trailing: Row(
                              // Fix for "No named parameter with the name 'trailing'."
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                IconButton(
                                  icon: Icon(
                                    Icons.check_circle_outline,
                                    color: Colors.green.shade500,
                                  ),
                                  onPressed: () {
                                    attendanceData.setAttendance(
                                      _selectedDate,
                                      student.registerNumber,
                                      widget.subject.code,
                                      AttendanceStatus.present,
                                    );
                                    ScaffoldMessenger.of(
                                      context,
                                    ).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Marked ${student.name} Present for ${widget.subject.code} on ${DateFormat('MMM d').format(_selectedDate)}',
                                        ),
                                        duration: const Duration(seconds: 1, milliseconds: 500),
                                      ),
                                    );
                                  },
                                  tooltip: 'Mark Present',
                                ),
                                IconButton(
                                  icon: Icon(
                                    Icons.cancel_outlined,
                                    color: Colors.red.shade500,
                                  ),
                                  onPressed: () {
                                    attendanceData.setAttendance(
                                      _selectedDate,
                                      student.registerNumber,
                                      widget.subject.code,
                                      AttendanceStatus.absent,
                                    );
                                    ScaffoldMessenger.of(
                                      context,
                                    ).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Marked ${student.name} Absent for ${widget.subject.code} on ${DateFormat('MMM d').format(_selectedDate)}',
                                        ),
                                        duration: const Duration(seconds: 1, milliseconds: 500),
                                      ),
                                    );
                                  },
                                  tooltip: 'Mark Absent',
                                ),
                                IconButton(
                                  icon: Icon(
                                    Icons
                                        .adjust, // Changed icon for Half Day
                                    color: Colors
                                        .orange
                                        .shade500, // Changed color for Half Day
                                  ),
                                  onPressed: () {
                                    attendanceData.setAttendance(
                                      _selectedDate,
                                      student.registerNumber,
                                      widget.subject.code,
                                      AttendanceStatus
                                          .halfday, // Changed to halfday
                                    );
                                    ScaffoldMessenger.of(
                                      context,
                                    ).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Marked ${student.name} Half Day for ${widget.subject.code} on ${DateFormat('MMM d').format(_selectedDate)}', // Changed text
                                        ),
                                        duration: const Duration(seconds: 1, milliseconds: 500),
                                      ),
                                    );
                                  },
                                  tooltip: 'Mark Half Day', // Changed tooltip
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Attendance for ${widget.subject.name} on ${DateFormat('MMM d, y').format(_selectedDate)} marked!',
                          ),
                          duration: const Duration(
                            seconds: 1,
                            milliseconds: 500,
                          ), // Reduced duration
                        ),
                      );
                    },
                    icon: const Icon(Icons.save),
                    label: const Text('Save Attendance'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      textStyle: const TextStyle(fontSize: 18),
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.primary,
                      foregroundColor: Theme.of(
                        context,
                      ).colorScheme.onPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Displays the list of students for attendance tracking.
class TeacherAttendancePage extends StatefulWidget {
  const TeacherAttendancePage({super.key});

  @override
  State<TeacherAttendancePage> createState() => _TeacherAttendancePageState();
}

class _TeacherAttendancePageState extends State<TeacherAttendancePage> {
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _selectedDate = DateUtils.dateOnly(DateTime.now());
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
      helpText: 'Select Attendance Date',
      cancelText: 'Cancel',
      confirmText: 'Select',
      builder: (BuildContext context, Widget? child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: ColorScheme.light(
              primary: Theme.of(context).colorScheme.primary,
              onPrimary: Theme.of(context).colorScheme.onPrimary,
              surface: Theme.of(context).colorScheme.surface,
              onSurface: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && DateUtils.dateOnly(picked) != _selectedDate) {
      setState(() {
        _selectedDate = DateUtils.dateOnly(picked);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Attendance date set to: ${DateFormat('EEEE, MMMM d, y').format(_selectedDate)}',
          ),
          duration: const Duration(seconds: 1, milliseconds: 500), // Reduced duration
        ),
      );
    }
  }

  Color _getCardColor(AttendanceStatus status, ThemeData theme) {
    switch (status) {
      case AttendanceStatus.present:
        return Colors.green.shade500.withAlpha(51);
      case AttendanceStatus.absent:
        return Colors.red.shade500.withAlpha(26);
      case AttendanceStatus.halfday: // New case for Half Day
        return Colors.orange.shade300.withAlpha(51);
      case AttendanceStatus.noclass: // Previously halfday/unknown
        return theme.cardColor;
    }
  }

  @override
  Widget build(BuildContext context) {
    return provider_lib.Consumer2<StudentData, AttendanceData>(
      builder: (
        BuildContext context,
        StudentData studentData,
        AttendanceData attendanceData,
        Widget? child,
      ) {
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                "Students for General Attendance",
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 8.0,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow:
                      Theme.of(context).brightness == Brightness.light
                          ? <BoxShadow>[
                              BoxShadow(
                                color: Colors.grey.withAlpha(25),
                                spreadRadius: 1,
                                blurRadius: 5,
                                offset: const Offset(0, 3),
                              ),
                            ]
                          : null,
                ),
                child: Row(
                  children: <Widget>[
                    Icon(
                      Icons.calendar_month,
                      color: Theme.of(context).colorScheme.primary,
                      size: 28,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        'Date: ${DateFormat('EEEE, MMM d, y').format(_selectedDate)}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.light
                            ? Colors.grey[200]
                            : Colors.grey[700],
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: Icon(
                          Icons.edit_calendar,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        onPressed: () => _selectDate(context),
                        tooltip: 'Change Attendance Date',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (studentData.students.isEmpty)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Icon(
                          Icons.group_off,
                          size: 60,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withAlpha(100),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          "No students added yet. Please add students in the 'Students' tab.",
                          style: TextStyle(
                            fontSize: 16,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withAlpha(178),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.builder(
                    itemCount: studentData.students.length,
                    itemBuilder: (BuildContext listContext, int index) {
                      final Student student = studentData.students[index];
                      // For general attendance, let's use a dummy subject code, or indicate it's not subject-specific.
                      // For simplicity, we'll use a constant 'GENERAL' subject code.
                      const String generalSubjectCode = 'GENERAL';
                      final AttendanceStatus currentStatus = attendanceData
                          .getAttendance(
                            _selectedDate,
                            student.registerNumber,
                            generalSubjectCode,
                          );
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4.0),
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        color: _getCardColor(
                          currentStatus,
                          Theme.of(context),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16.0,
                            vertical: 8.0,
                          ),
                          leading: Icon(
                            Icons.person_outline,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          title: Text(
                            student.name,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                              color: Theme.of(
                                listContext,
                              ).colorScheme.onSurface,
                            ),
                          ),
                          subtitle: Text(
                            student.registerNumber.isNotEmpty
                                ? 'Reg. No: ${student.registerNumber}'
                                : 'No Register Number',
                            style: TextStyle(
                              fontSize: 14,
                              color: Theme.of(
                                listContext,
                              ).colorScheme.onSurface.withAlpha(178),
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              IconButton(
                                icon: Icon(
                                  Icons.check_circle_outline,
                                  color: Colors.green.shade500,
                                ),
                                onPressed: () {
                                  attendanceData.setAttendance(
                                    _selectedDate,
                                    student.registerNumber,
                                    generalSubjectCode,
                                    AttendanceStatus.present,
                                  );
                                  ScaffoldMessenger.of(
                                    context,
                                  ).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Marked ${student.name} Present for ${DateFormat('MMM d, y').format(_selectedDate)}',
                                      ),
                                      duration: const Duration(seconds: 1, milliseconds: 500),
                                    ),
                                  );
                                },
                                tooltip: 'Mark Present',
                              ),
                              IconButton(
                                icon: Icon(
                                  Icons.cancel_outlined,
                                  color: Colors.red.shade500,
                                ),
                                onPressed: () {
                                  attendanceData.setAttendance(
                                    _selectedDate,
                                    student.registerNumber,
                                    generalSubjectCode,
                                    AttendanceStatus.absent,
                                  );
                                  ScaffoldMessenger.of(
                                    context,
                                  ).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Marked ${student.name} Absent for ${DateFormat('MMM d, y').format(_selectedDate)}',
                                      ),
                                      duration: const Duration(seconds: 1, milliseconds: 500),
                                    ),
                                  );
                                },
                                tooltip: 'Mark Absent',
                              ),
                              IconButton(
                                icon: Icon(
                                  Icons.adjust, // Changed icon for Half Day
                                  color: Colors
                                      .orange
                                      .shade500, // Changed color for Half Day
                                ),
                                onPressed: () {
                                  attendanceData.setAttendance(
                                    _selectedDate,
                                    student.registerNumber,
                                    generalSubjectCode,
                                    AttendanceStatus
                                        .halfday, // Changed to halfday
                                  );
                                  ScaffoldMessenger.of(
                                    context,
                                  ).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Marked ${student.name} Half Day for ${DateFormat('MMM d, y').format(_selectedDate)}', // Changed text
                                      ),
                                      duration: const Duration(seconds: 1, milliseconds: 500),
                                    ),
                                  );
                                },
                                tooltip: 'Mark Half Day', // Changed tooltip
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'General attendance for ${DateFormat('MMM d, y').format(_selectedDate)} submitted!',
                        ),
                        duration: const Duration(
                          seconds: 1,
                          milliseconds: 500,
                        ), // Reduced duration
                      ),
                    );
                    Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (BuildContext context) =>
                            const TeacherStudentOverallAttendancePage(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.check_circle),
                  label: const Text('Submit & View General Summary'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    textStyle: const TextStyle(fontSize: 18),
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(
                      context,
                    ).colorScheme.onPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A container for settings sections, with adaptive styling.
class SettingsSectionContainer extends StatelessWidget {
  final List<Widget> children;
  const SettingsSectionContainer({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF2C2C2E)
            : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: Theme.of(context).brightness == Brightness.light
            ? <BoxShadow>[
                BoxShadow(
                  color: Colors.grey.withAlpha(25),
                  spreadRadius: 1,
                  blurRadius: 5,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: Column(children: children),
    );
  }
}

/// A header for a settings section.
class SettingsSectionHeader extends StatelessWidget {
  final String title;
  const SettingsSectionHeader({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.grey[400]
              : Colors.grey[700],
        ),
      ),
    );
  }
}

/// A row for theme options (dark theme switch).
class ThemeOptionRow extends StatelessWidget {
  const ThemeOptionRow({super.key}); // Re-added const

  @override
  Widget build(BuildContext context) {
    return provider_lib.Consumer<AppSettings>(
      builder: (BuildContext context, AppSettings appSettings, Widget? child) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Row(
            children: <Widget>[
              Icon(
                Icons.brightness_medium,
                color: Theme.of(context).colorScheme.primary,
                size: 24,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      "Theme Mode",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      "Switch between Light or Dark theme.",
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withAlpha(178),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              ToggleButtons(
                isSelected: <bool>[
                  appSettings.selectedThemeMode == ThemeMode.light,
                  appSettings.selectedThemeMode == ThemeMode.dark,
                ],
                onPressed: (int index) {
                  if (index == 0) {
                    appSettings.selectedThemeMode = ThemeMode.light;
                  } else if (index == 1) {
                    appSettings.selectedThemeMode = ThemeMode.dark;
                  }
                },
                borderRadius: BorderRadius.circular(8.0),
                selectedColor: Theme.of(context).colorScheme.onPrimary,
                fillColor: Theme.of(context).colorScheme.primary,
                selectedBorderColor: Theme.of(context).colorScheme.primary,
                color: Theme.of(context).colorScheme.onSurface,
                children: const <Widget>[
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8.0),
                    child: Row(
                      children: <Widget>[
                        Icon(Icons.wb_sunny, size: 18),
                        SizedBox(width: 4),
                        Text('Light'),
                      ],
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8.0),
                    child: Row(
                      children: <Widget>[
                        Icon(Icons.nightlight_round, size: 18),
                        SizedBox(width: 4),
                        Text('Dark'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Utility class for showing share options.
class ShareUtils {
  static Future<void> _launchUrlAndShowFeedback(
    Uri uri,
    String appName,
    BuildContext context,
  ) async {
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not launch $appName. Ensure the app is installed or try another option.',
            ),
            duration: const Duration(seconds: 1, milliseconds: 500),
          ),
        );
      } else {
        debugPrint('Successfully launched $appName');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error launching $appName: $e'),
          duration: const Duration(seconds: 1, milliseconds: 500),
        ),
      );
    }
  }

  static Future<void> _copyToClipboardAndShowFeedback(
    BuildContext context,
    String text,
  ) async {
    await Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied to clipboard!'),
        duration: Duration(seconds: 1, milliseconds: 500), // Reduced duration
      ),
    );
  }

  /// Shows share options for a generic text string.
  static Future<void> showGenericShareDialog(
    BuildContext context,
    String title,
    String content,
  ) async {
    final String encodedContent = Uri.encodeComponent(content);

    showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(sheetContext).colorScheme.onSurface,
                  ),
                ),
              ),
              ListTile(
                leading: Icon(
                  Icons.email,
                  color: Theme.of(sheetContext).colorScheme.primary,
                ),
                title: const Text('Share via Email'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  final Uri emailLaunchUri = Uri(
                    scheme: 'mailto',
                    query:
                        'subject=${Uri.encodeComponent(title)}&body=$encodedContent',
                  );
                  _launchUrlAndShowFeedback(
                    emailLaunchUri,
                    'email app',
                    context,
                  );
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.sms,
                  color: Theme.of(sheetContext).colorScheme.primary,
                ),
                title: const Text('Share via SMS'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  final Uri smsLaunchUri = Uri(
                    scheme: 'sms',
                    path: '', // Optional: recipient number
                    queryParameters: <String, String>{'body': content},
                  );
                  _launchUrlAndShowFeedback(smsLaunchUri, 'SMS app', context);
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.chat_bubble,
                  color: Colors.green.shade700,
                ), // Generic chat icon for WhatsApp
                title: const Text('Share via WhatsApp'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  final Uri whatsappLaunchUri = Uri.parse(
                    'https://wa.me/?text=$encodedContent',
                  );
                  _launchUrlAndShowFeedback(
                    whatsappLaunchUri,
                    'WhatsApp',
                    context,
                  );
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.copy,
                  color: Theme.of(sheetContext).colorScheme.onSurface,
                ),
                title: const Text('Copy to Clipboard'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _copyToClipboardAndShowFeedback(context, content);
                },
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  /// Shows share options specifically for app information.
  static Future<void> showAppShareOptionsDialog(
    BuildContext context,
    AppSettings appSettings,
  ) async {
    final String shareText =
        appSettings.getShareMessageTextSpan().toPlainText();
    return showGenericShareDialog(
      context,
      'Share ${appSettings.appName}',
      shareText,
    );
  }
}

/// A row for app sharing.
class AppSharingRow extends StatelessWidget {
  const AppSharingRow({super.key}); // Re-added const

  @override
  Widget build(BuildContext context) {
    return provider_lib.Consumer<AppSettings>(
      builder: (BuildContext context, AppSettings appSettings, Widget? child) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Row(
            children: <Widget>[
              Icon(Icons.share, color: Colors.blueAccent, size: 24),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      "Share App",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      "Help us grow by sharing the app with your friends.",
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withAlpha(178),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                onPressed: () =>
                    ShareUtils.showAppShareOptionsDialog(context, appSettings),
                icon: const Icon(Icons.send),
                label: const Text("Share Now"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A row for daily reminder settings.
class NotificationSettingRow extends StatelessWidget {
  const NotificationSettingRow({super.key}); // Re-added const

  @override
  Widget build(BuildContext context) {
    return provider_lib.Consumer<AppSettings>(
      builder: (BuildContext context, AppSettings appSettings, Widget? child) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Row(
            children: <Widget>[
              Icon(
                Icons.notifications_active,
                color: Theme.of(context).colorScheme.primary,
                size: 24,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      "Daily Attendance Reminder",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      "Get a daily reminder at 2:00 PM to submit attendance.",
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withAlpha(178),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Switch(
                value: appSettings.dailyReminderEnabled,
                onChanged: (bool newValue) {
                  appSettings.dailyReminderEnabled = newValue;
                },
                thumbColor: WidgetStateProperty.resolveWith<Color?>(
                  (Set<WidgetState> states) {
                    if (states.contains(WidgetState.selected)) {
                      return Theme.of(context)
                          .colorScheme
                          .primary; // Active thumb color
                    }
                    return Colors.black; // Inactive thumb color
                  },
                ),
                trackColor: WidgetStateProperty.resolveWith<Color?>(
                  (Set<WidgetState> states) {
                    if (states.contains(WidgetState.selected)) {
                      return Theme.of(context)
                          .colorScheme
                          .primary
                          .withOpacity(0.5); // Active track color
                    }
                    return Theme.of(context).brightness == Brightness.dark
                        ? Colors.grey.shade700 // Dark grey track for dark mode OFF
                        : Colors.grey.shade400; // Light grey track for light mode OFF
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A row for backup/restore actions.
class BackupRestoreRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String buttonText;
  final VoidCallback onPressed;

  const BackupRestoreRow({
    // Re-added const
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.buttonText,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: <Widget>[
          Icon(icon, color: iconColor, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withAlpha(178),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          OutlinedButton(
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: Theme.of(context).colorScheme.primary),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.0),
              ),
            ),
            child: Text(buttonText),
          ),
        ],
      ),
    );
  }
}

/// Utility for handling data export/import logic.
class DataManagementUtils {
  static String _escapeCsv(String? value) {
    if (value == null || value.isEmpty) return '';
    String escaped = value.replaceAll('"', '""'); // Escape double quotes
    if (escaped.contains(',') ||
        escaped.contains('"') ||
        escaped.contains('\n')) {
      return '"$escaped"'; // Enclose in double quotes if it contains special characters
    }
    return escaped;
  }

  /// Generates a CSV string for general attendance records.
  static String _generateGeneralAttendanceCsv({
    required AttendanceData attendanceData,
    required StudentData studentData,
    required StudentSubjectsModel studentSubjectsModel,
    required TeacherSubjectsData teacherSubjectsData,
    String? forStudentRegisterNumber, // Optional: filter for a specific student
  }) {
    final StringBuffer csvBuffer = StringBuffer();
    // CSV Header for General Attendance
    csvBuffer.writeln('Date,Register Number,Student Name,Attendance Status');

    final List<Map<String, dynamic>> generalRecords = <Map<String, dynamic>>[];
    const String generalSubjectCode = 'GENERAL';

    final Map<DateTime, Map<String, AttendanceStatus>>? dailyGeneralRecords =
        attendanceData._attendanceRecords[generalSubjectCode];

    if (dailyGeneralRecords != null) {
      dailyGeneralRecords.forEach((
        DateTime date,
        Map<String, AttendanceStatus> studentStatusMap,
      ) {
        studentStatusMap.forEach((String regNum, AttendanceStatus status) {
          if (forStudentRegisterNumber == null ||
              regNum == forStudentRegisterNumber) {
            generalRecords.add(<String, dynamic>{
              'date': date,
              'regNum': regNum,
              'status': status,
            });
          }
        });
      });
    }

    generalRecords.sort((Map<String, dynamic> a, Map<String, dynamic> b) {
      final int dateComparison = (a['date'] as DateTime).compareTo(
        b['date'] as DateTime,
      );
      if (dateComparison != 0) return dateComparison;
      return (a['regNum'] as String).compareTo(b['regNum'] as String);
    });

    for (final Map<String, dynamic> record in generalRecords) {
      final DateTime date = record['date'] as DateTime;
      final String regNum = record['regNum'] as String;
      final AttendanceStatus status = record['status'] as AttendanceStatus;

      final Student? student = studentData.students.firstWhereOrNull(
        (Student s) => s.registerNumber == regNum,
      );
      final String studentName = student?.name ?? 'Unknown Student';

      final String formattedDate = DateFormat('yyyy-MM-dd').format(date);
      csvBuffer.writeln(
        '"$formattedDate","$regNum","${_escapeCsv(studentName)}","${status.name}"',
      );
    }
    return csvBuffer.toString();
  }

  /// Generates a CSV string for subject-specific attendance records.
  static String _generateSubjectSpecificAttendanceCsv({
    required AttendanceData attendanceData,
    required StudentData studentData,
    required StudentSubjectsModel studentSubjectsModel,
    required TeacherSubjectsData teacherSubjectsData,
    String? forStudentRegisterNumber, // Optional: filter for a specific student
  }) {
    final StringBuffer csvBuffer = StringBuffer();
    // CSV Header for Subject-Specific Attendance
    csvBuffer.writeln(
      'Date,Register Number,Student Name,Subject Code,Subject Name,Attendance Status',
    );

    final List<Map<String, dynamic>> subjectSpecificRecords =
        <Map<String, dynamic>>[];
    const String generalSubjectCode =
        'GENERAL'; // Exclude this from subject-specific

    attendanceData._attendanceRecords.forEach((
      String subjectCode,
      Map<DateTime, Map<String, AttendanceStatus>> subjectDailyRecords,
    ) {
      if (subjectCode == generalSubjectCode) {
        return; // Skip general attendance for this export
      }

      subjectDailyRecords.forEach((
        DateTime date,
        Map<String, AttendanceStatus> studentStatusMap,
      ) {
        studentStatusMap.forEach((String regNum, AttendanceStatus status) {
          if (forStudentRegisterNumber == null ||
              regNum == forStudentRegisterNumber) {
            subjectSpecificRecords.add(<String, dynamic>{
              'date': date,
              'regNum': regNum,
              'subjectCode': subjectCode,
              'status': status,
            });
          }
        });
      });
    });

    subjectSpecificRecords.sort((Map<String, dynamic> a, Map<String, dynamic> b) {
      final int dateComparison = (a['date'] as DateTime).compareTo(
        b['date'] as DateTime,
      );
      if (dateComparison != 0) return dateComparison;

      final int regNumComparison = (a['regNum'] as String).compareTo(
        b['regNum'] as String,
      );
      if (regNumComparison != 0) return regNumComparison;

      return (a['subjectCode'] as String).compareTo(b['subjectCode'] as String);
    });

    for (final Map<String, dynamic> record in subjectSpecificRecords) {
      final DateTime date = record['date'] as DateTime;
      final String regNum = record['regNum'] as String;
      final String subjectCode = record['subjectCode'] as String;
      final AttendanceStatus status = record['status'] as AttendanceStatus;

      final Student? student = studentData.students.firstWhereOrNull(
        (Student s) => s.registerNumber == regNum,
      );
      final String studentName = student?.name ?? 'Unknown Student';

      final String subjectName = resolveSubjectNameForDisplay(
        subjectCode,
        studentSubjectsModel.subjects,
        teacherSubjectsData.subjects,
      );

      final String formattedDate = DateFormat('yyyy-MM-dd').format(date);
      csvBuffer.writeln(
        '"$formattedDate","$regNum","${_escapeCsv(studentName)}","${_escapeCsv(subjectCode)}","${_escapeCsv(subjectName)}","${status.name}"',
      );
    }
    return csvBuffer.toString();
  }

  /// Displays the modal bottom sheet with options to open/download or view/share CSV content.
  static Future<void> _showExportOptionsDialog(
    BuildContext context,
    String title,
    String csvContent,
  ) async {
    showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(sheetContext).colorScheme.onSurface,
                  ),
                ),
              ),
              ListTile(
                leading: Icon(
                  Icons.download,
                  color: Theme.of(sheetContext).colorScheme.primary,
                ),
                title: const Text('Open/Download CSV Data'), // Clarified title
                onTap: () async {
                  Navigator.pop(sheetContext); // Pop the bottom sheet
                  final String encodedCsvContent = Uri.encodeComponent(
                    csvContent,
                  );
                  final Uri dataUri = Uri.parse(
                    'data:text/csv;charset=utf-8,$encodedCsvContent',
                  );

                  try {
                    if (!await launchUrl(
                      dataUri,
                      mode: LaunchMode.externalApplication, // Use externalApplication
                    )) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Could not open data. Please ensure you have an app that can handle CSV data or try "View & Share Data".',
                          ),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'CSV data sent to an external application (e.g., browser). You may be able to download/save from there.',
                          ),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    }
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error attempting to open data: $e. Try "View & Share Data".'),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.visibility,
                  color: Theme.of(sheetContext).colorScheme.secondary,
                ),
                title: const Text('View & Share Data'),
                onTap: () {
                  Navigator.pop(sheetContext); // Pop the bottom sheet
                  showDialog<void>(
                    context: context,
                    builder: (BuildContext dialogContext) {
                      return AlertDialog(
                        title: Text(title),
                        content: SizedBox(
                          width: MediaQuery.of(dialogContext).size.width * 0.8,
                          height:
                              MediaQuery.of(dialogContext).size.height * 0.6,
                          child: SingleChildScrollView(
                            child: SelectableText(
                              csvContent,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                        actions: <Widget>[
                          TextButton(
                            onPressed: () async {
                              await Clipboard.setData(
                                ClipboardData(text: csvContent),
                              );
                              ScaffoldMessenger.of(dialogContext).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Data copied to clipboard!',
                                  ),
                                  duration: Duration(seconds: 1, milliseconds: 500),
                                ),
                              );
                            },
                            child: const Text('Copy All'),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.pop(dialogContext); // Pop AlertDialog
                              ShareUtils.showGenericShareDialog(
                                context,
                                title,
                                csvContent,
                              );
                            },
                            child: const Text('Share'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            child: const Text('Close'),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  /// Exports general attendance data to an Excel-compatible CSV format and presents sharing options.
  static Future<void> exportGeneralAttendance(
    BuildContext context, {
    String? forStudentRegisterNumber,
  }) async {
    // This is the modified section
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Export Functionality'),
          content: const Text('This functionality Coming soon, Keep Using the App'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  /// Exports subject-specific attendance data to an Excel-compatible CSV format and presents sharing options.
  static Future<void> exportSubjectSpecificAttendance(
    BuildContext context, {
    String? forStudentRegisterNumber,
  }) async {
    // This is the modified section
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Export Functionality'),
          content: const Text('This functionality Coming soon, Keep Using the App'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }
}

/// A new page for the Teacher's Settings section.
class TeacherSettingsPage extends StatelessWidget {
  const TeacherSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              "Teacher Settings",
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 24),
            const SettingsSectionHeader(title: "General"),
            const SizedBox(height: 8),
            const SettingsSectionContainer(
              children: <Widget>[
                ThemeOptionRow(), // Added const
                Divider(height: 1, thickness: 0.5),
                NotificationSettingRow(), // Added const
              ],
            ),
            // Data Management Section
            const SizedBox(height: 24),
            const SettingsSectionHeader(title: "Data Management"),
            const SizedBox(height: 8),
            SettingsSectionContainer(
              children: <Widget>[
                BackupRestoreRow(
                  icon:
                      Icons.grid_on, // Changed icon for attendance/CSV to grid
                  iconColor:
                      Colors.purple.shade400, // Different color for general
                  title: "Export General Attendance (CSV)",
                  subtitle:
                      "Export all students' general attendance records (not subject-specific).",
                  buttonText: "Export",
                  onPressed: () =>
                      DataManagementUtils.exportGeneralAttendance(context),
                ),
                const Divider(height: 1, thickness: 0.5),
                BackupRestoreRow(
                  icon: Icons.article, // Different icon for subject specific
                  iconColor:
                      Colors.teal.shade400, // Changed color for spreadsheet
                  title: "Export Subject Attendance (CSV)", // Changed title
                  subtitle:
                      "Export all students' subject-specific attendance records.", // Changed subtitle
                  buttonText: "Export", // Changed button text
                  onPressed: () =>
                      DataManagementUtils.exportSubjectSpecificAttendance(
                        context,
                      ), // Changed function call
                ),
              ],
            ),
            const SizedBox(height: 24),
            const SettingsSectionHeader(title: "About"),
            const SizedBox(height: 8),
            const SettingsSectionContainer(
              children: <Widget>[
                AppSharingRow(), // Added const
                Divider(height: 1, thickness: 0.5),
              ],
            ),
            const SizedBox(height: 24),
            Center(
              child: OutlinedButton.icon(
                onPressed: () {
                  // Reset user role to unselected and pop to RoleSelectionPage
                  provider_lib.Provider.of<UserSession>(
                    context,
                    listen: false,
                  ).userRole = UserRole.unselected;
                  Navigator.of(
                    context,
                  ).popUntil((route) => route.isFirst); // Go back to root page
                },
                icon: const Icon(Icons.logout),
                label: const Text('Change Role / Logout'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                  side: BorderSide(color: Theme.of(context).colorScheme.error),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  textStyle: const TextStyle(fontSize: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16), // Padding at the bottom
          ],
        ),
      ),
    );
  }
}

/// A new main screen for students with internal navigation.
class StudentsMainScreen extends StatefulWidget {
  const StudentsMainScreen({super.key});

  @override
  State<StudentsMainScreen> createState() => _StudentsMainScreenState();
}

class _StudentsMainScreenState extends State<StudentsMainScreen>
    with TickerProviderStateMixin {
  int _selectedIndex = 0;
  late final PageController _pageController;

  late final List<Widget> _studentPages;

  final List<String> _pageTitles = <String>[
    "Student Home", // Renamed for clarity
    "My Attendance",
    "My Subjects",
    "Settings",
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _selectedIndex);
    _studentPages = <Widget>[
      StudentHomePage(onNavigateToTab: _onItemTapped), // Pass the callback
      const MyAttendancePage(), // Existing page, now used as a tab content
      const StudentSubjectsPage(), // New page for student subjects
      const StudentSettingsPage(), // New page for student settings
    ];
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.ease,
    );
  }

  void _showAddStudentProfileDialog(BuildContext contextForProvider) {
    final TextEditingController studentNameController = TextEditingController();
    final TextEditingController registerNumberController =
        TextEditingController();

    showDialog<void>(
      context: contextForProvider,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Add Your Profile'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(
                  controller: studentNameController,
                  decoration: InputDecoration(
                    labelText: 'Your Name *',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.0),
                      borderSide: BorderSide(
                        color: Theme.of(contextForProvider).colorScheme.primary,
                        width: 2.0,
                      ),
                    ),
                    floatingLabelStyle: TextStyle(
                      color: Theme.of(contextForProvider).colorScheme.primary,
                    ),
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: registerNumberController,
                  decoration: InputDecoration(
                    labelText: 'Register Number (Optional)',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.0),
                      borderSide: BorderSide(
                        color: Theme.of(contextForProvider).colorScheme.primary,
                        width: 2.0,
                      ),
                    ),
                    floatingLabelStyle: TextStyle(
                      color: Theme.of(contextForProvider).colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                studentNameController.dispose();
                registerNumberController.dispose();
                Navigator.pop(dialogContext);
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final String newStudentName = studentNameController.text.trim();
                final String newRegisterNumber =
                    registerNumberController.text.trim();

                if (newStudentName.isNotEmpty) {
                  final CurrentStudentProfile currentStudentProfile =
                      provider_lib.Provider.of<CurrentStudentProfile>(
                    contextForProvider,
                    listen: false,
                  );
                  final Student newStudent = Student(
                    name: newStudentName,
                    registerNumber: newRegisterNumber,
                  );

                  // Update or set the current student profile
                  currentStudentProfile.setProfile(newStudent);

                  Navigator.pop(dialogContext);
                  ScaffoldMessenger.of(contextForProvider).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Your profile "$newStudentName"${newRegisterNumber.isNotEmpty ? ' (Reg. No: $newRegisterNumber)' : ''} added/updated!',
                      ),
                      duration: const Duration(seconds: 1, milliseconds: 500),
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(contextForProvider).showSnackBar(
                    const SnackBar(
                      content: Text('Your name cannot be empty.'),
                      duration: Duration(seconds: 1, milliseconds: 500),
                    ),
                  );
                }
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    ).then((_) {
      studentNameController.dispose();
      registerNumberController.dispose();
    });
  }

  void _showAddStudentSubjectDialog(BuildContext contextForProvider) {
    final TextEditingController subjectNameController = TextEditingController();
    final TextEditingController subjectCodeController = TextEditingController();

    showDialog<void>(
      context: contextForProvider,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Add New Subject'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(
                  controller: subjectNameController,
                  decoration: InputDecoration(
                    labelText: 'Subject Name *',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.0),
                      borderSide: BorderSide(
                        color: Theme.of(contextForProvider).colorScheme.primary,
                        width: 2.0,
                      ),
                    ),
                    floatingLabelStyle: TextStyle(
                      color: Theme.of(contextForProvider).colorScheme.primary,
                    ),
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: subjectCodeController,
                  decoration: InputDecoration(
                    labelText: 'Subject Code *', // Now required
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.0),
                      borderSide: BorderSide(
                        color: Theme.of(contextForProvider).colorScheme.primary,
                        width: 2.0,
                      ),
                    ),
                    floatingLabelStyle: TextStyle(
                      color: Theme.of(contextForProvider).colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                subjectNameController.dispose();
                subjectCodeController.dispose();
                Navigator.pop(dialogContext);
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final String newSubjectName = subjectNameController.text.trim();
                final String newSubjectCode = subjectCodeController.text.trim();

                if (newSubjectName.isEmpty) {
                  ScaffoldMessenger.of(contextForProvider).showSnackBar(
                    const SnackBar(
                      content: Text('Subject name cannot be empty.'),
                      duration: Duration(seconds: 1, milliseconds: 500),
                    ),
                  );
                  return;
                }
                if (newSubjectCode.isEmpty) {
                  ScaffoldMessenger.of(contextForProvider).showSnackBar(
                    const SnackBar(
                      content: Text('Subject code cannot be empty.'),
                      duration: Duration(seconds: 1, milliseconds: 500),
                    ),
                  );
                  return;
                }

                final StudentSubjectsModel subjectsData =
                    provider_lib.Provider.of<StudentSubjectsModel>(
                  contextForProvider,
                  listen: false,
                );
                subjectsData.addSubject(newSubjectName, newSubjectCode);
                Navigator.pop(dialogContext);
                ScaffoldMessenger.of(contextForProvider).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Subject "$newSubjectName" (Code: $newSubjectCode) added!',
                    ),
                    duration: const Duration(seconds: 1, milliseconds: 500),
                  ),
                );
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    ).then((_) {
      subjectNameController.dispose();
      subjectCodeController.dispose();
    });
  }

  void _showSuggestFeatureDialog() {
    final TextEditingController suggestionController = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Suggest a Feature'),
          content: TextField(
            controller: suggestionController,
            decoration: InputDecoration(
              labelText: 'Your Suggestion',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8.0),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8.0),
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2.0,
                ),
              ),
              floatingLabelStyle: TextStyle(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            autofocus: true,
            maxLines: 3,
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                suggestionController.dispose();
                Navigator.pop(dialogContext);
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final String suggestion = suggestionController.text.trim();
                if (suggestion.isNotEmpty) {
                  debugPrint('User suggested feature: $suggestion');
                  Navigator.pop(dialogContext);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Thank you for your suggestion: "$suggestion"!',
                      ),
                      duration: const Duration(
                        seconds: 1,
                        milliseconds: 500,
                      ), // Reduced duration
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Suggestion cannot be empty.'),
                      duration: Duration(seconds: 1, milliseconds: 500), // Reduced duration
                    ),
                  );
                }
              },
              child: const Text('Submit'),
            ),
          ],
        );
      },
    ).then((_) {
      suggestionController.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _pageTitles[_selectedIndex],
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        foregroundColor: Theme.of(context).appBarTheme.foregroundColor,
        elevation: 4,
        actions: <Widget>[
          if (_selectedIndex == 3) // Settings tab
            IconButton(
              icon: Icon(
                Icons.share,
                color: Theme.of(context).appBarTheme.foregroundColor,
              ),
              onPressed: () {
                final AppSettings appSettings = provider_lib
                    .Provider.of<AppSettings>(context, listen: false);
                ShareUtils.showAppShareOptionsDialog(context, appSettings);
              },
            ),
        ],
      ),
      body: PageView(
        controller: _pageController,
        onPageChanged: (int index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        children: _studentPages,
      ),
      floatingActionButton:
          (_selectedIndex == 0 || _selectedIndex == 2 || _selectedIndex == 3)
              ? provider_lib.Consumer<CurrentStudentProfile>(
                  builder: (
                    BuildContext consumerContext,
                    CurrentStudentProfile currentStudentProfile,
                    Widget? child,
                  ) {
                    if (_selectedIndex == 0 &&
                        currentStudentProfile.profile == null) {
                      // On Home tab, if no profile exists, show Add Profile FAB
                      return FloatingActionButton(
                        heroTag: 'addStudentProfileFab',
                        onPressed: () => _showAddStudentProfileDialog(context),
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.secondary,
                        tooltip: 'Add Your Student Profile',
                        child: const Icon(Icons.person_add),
                      );
                    } else if (_selectedIndex == 2 &&
                        currentStudentProfile.profile != null) {
                      // On Subjects tab, if a profile exists, show Add Subject FAB
                      return FloatingActionButton(
                        heroTag: 'addStudentSubjectFab',
                        onPressed: () => _showAddStudentSubjectDialog(context),
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.secondary,
                        tooltip: 'Add New Subject',
                        child: const Icon(Icons.add),
                      );
                    } else if (_selectedIndex == 3) {
                      // On Settings tab, show Suggest Feature FAB
                      return FloatingActionButton(
                        heroTag: 'suggestFeatureFab',
                        onPressed: _showSuggestFeatureDialog,
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.secondary,
                        tooltip: 'Suggest New Feature',
                        child: const Icon(Icons.lightbulb_outline),
                      );
                    }
                    return const SizedBox
                        .shrink(); // Hide FAB for other cases/tabs
                  },
                )
              : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(
            icon: Icon(Icons.check_box),
            label: 'Attendance',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.book), label: 'Subjects'),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Theme.of(context).colorScheme.primary,
        unselectedItemColor: Colors.grey,
        onTap: _onItemTapped,
        type: BottomNavigationBarType.fixed,
        backgroundColor: Theme.of(context).colorScheme.surface,
      ),
    );
  }
}

/// New placeholder page for Student Home.
class StudentHomePage extends StatelessWidget {
  final Function(int) onNavigateToTab;
  const StudentHomePage({super.key, required this.onNavigateToTab});

  @override
  Widget build(BuildContext context) {
    return provider_lib.Consumer<CurrentStudentProfile>(
      builder: (
        BuildContext consumerContext,
        CurrentStudentProfile currentStudentProfile,
        Widget? child,
      ) {
        final Student? currentStudent = currentStudentProfile.profile;

        return Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(
                  Icons.person,
                  size: 80,
                  color: Theme.of(consumerContext).colorScheme.primary,
                ),
                const SizedBox(height: 20),
                Text(
                  currentStudent != null
                      ? "Welcome, ${currentStudent.name}!"
                      : "Welcome, Student!",
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(consumerContext).colorScheme.onSurface,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                if (currentStudent == null)
                  Card(
                    elevation: 4,
                    margin: const EdgeInsets.all(16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: <Widget>[
                          Text(
                            "You don't have a profile yet.",
                            style: TextStyle(
                              fontSize: 16,
                              color: Theme.of(
                                consumerContext,
                              ).colorScheme.onSurface.withAlpha(178),
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            "Tap the '+' button below to create yours and start tracking attendance.",
                            style: TextStyle(
                              fontSize: 16,
                              color: Theme.of(
                                consumerContext,
                              ).colorScheme.onSurface.withAlpha(178),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Text(
                    "Your personalized student dashboard.",
                    style: TextStyle(
                      fontSize: 16,
                      color: Theme.of(
                        consumerContext,
                      ).colorScheme.onSurface.withAlpha(178),
                    ),
                    textAlign: TextAlign.center,
                  ),
                const SizedBox(height: 30),
                if (currentStudent != null)
                  ElevatedButton.icon(
                    onPressed: () {
                      // Navigate to My Attendance page (which is a tab now)
                      onNavigateToTab(1); // Index of My Attendance tab
                    },
                    icon: const Icon(Icons.calendar_today),
                    label: const Text('View Today\'s Attendance'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 15,
                      ),
                      textStyle: const TextStyle(fontSize: 18),
                      backgroundColor: Theme.of(
                        consumerContext,
                      ).colorScheme.secondary,
                      foregroundColor: Theme.of(
                        consumerContext,
                      ).colorScheme.onSecondary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// New page for Student Subjects, allowing adding and viewing subjects.
class StudentSubjectsPage extends StatefulWidget {
  const StudentSubjectsPage({super.key});

  @override
  State<StudentSubjectsPage> createState() => _StudentSubjectsPageState();
}

class _StudentSubjectsPageState extends State<StudentSubjectsPage> {
  Future<void> _confirmRemoveSubject(StudentSubject subject) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Confirm Deletion'),
          content: Text(
            'Are you sure you want to remove "${subject.name}"${subject.subjectCode.isNotEmpty ? ' (Code: ${subject.subjectCode})' : ''} from your subjects?',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      final StudentSubjectsModel subjectsData =
          provider_lib.Provider.of<StudentSubjectsModel>(context, listen: false);
      subjectsData.removeSubject(subject);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Subject "${subject.name}" removed.'),
          duration: const Duration(seconds: 1, milliseconds: 500),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return provider_lib.Consumer2<StudentSubjectsModel, CurrentStudentProfile>(
      builder: (
        BuildContext context,
        StudentSubjectsModel subjectsData,
        CurrentStudentProfile currentStudentProfile,
        Widget? child,
      ) {
        // This page only makes sense if a student profile exists.
        if (currentStudentProfile.profile == null) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(
                  Icons.person_off,
                  size: 80,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withAlpha(100),
                ),
                const SizedBox(height: 20),
                Text(
                  "No student profile found.",
                  style: TextStyle(
                    fontSize: 18,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withAlpha(178),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  "Please add your profile in the Home tab first.",
                  style: TextStyle(
                    fontSize: 16,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withAlpha(178),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                "Your Enrolled Subjects",
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 16),
              if (subjectsData.subjects.isEmpty)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Icon(
                          Icons.inbox,
                          size: 60,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withAlpha(100),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          "No subjects added yet. Tap the '+' button to add one!",
                          style: TextStyle(
                            fontSize: 16,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withAlpha(178),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.builder(
                    itemCount: subjectsData.subjects.length,
                    itemBuilder: (BuildContext listContext, int index) {
                      final StudentSubject subject =
                          subjectsData.subjects[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4.0),
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16.0,
                            vertical: 8.0,
                          ),
                          leading: Icon(
                            Icons.book_outlined,
                            color: Theme.of(
                              listContext,
                            ).colorScheme.secondary,
                          ),
                          title: Text(
                            subject.name,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                              color: Theme.of(
                                listContext,
                              ).colorScheme.onSurface,
                            ),
                          ),
                          subtitle: Text(
                            subject.subjectCode.isNotEmpty
                                ? 'Code: ${subject.subjectCode}'
                                : 'No Code',
                            style: TextStyle(
                              fontSize: 14, // Fixed font size
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withAlpha(178),
                            ),
                          ),
                          trailing: IconButton(
                            icon: Icon(
                              Icons.delete,
                              color: Theme.of(context).colorScheme.error,
                            ),
                            onPressed: () => _confirmRemoveSubject(subject),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// A new page for the Student's Settings section.
class StudentSettingsPage extends StatelessWidget {
  const StudentSettingsPage({super.key});

  Future<void> _confirmRemoveStudentProfile(
    BuildContext context,
    Student student,
  ) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Confirm Profile Deletion'),
          content: Text(
            'Are you sure you want to remove your profile "${student.name}"${student.registerNumber.isNotEmpty ? ' (Reg. No: ${student.registerNumber})' : ''}?\n\nThis will also clear all your attendance records and subjects.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      final CurrentStudentProfile currentStudentProfile = provider_lib
          .Provider.of<CurrentStudentProfile>(context, listen: false);
      final StudentSubjectsModel studentSubjectsModel = provider_lib
          .Provider.of<StudentSubjectsModel>(context, listen: false);
      final AttendanceData attendanceData =
          provider_lib.Provider.of<AttendanceData>(context, listen: false);

      // Clear current student profile
      await currentStudentProfile.clearProfile();
      // Clear all subjects associated with the student user
      await studentSubjectsModel.clearAllSubjects();
      // Clear attendance records for this specific student
      await attendanceData.clearAttendanceForStudent(student.registerNumber);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Your profile "${student.name}" removed.'),
          duration: const Duration(seconds: 1, milliseconds: 500),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              "Student Settings",
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 24),
            const SettingsSectionHeader(title: "General"),
            const SizedBox(height: 8),
            const SettingsSectionContainer(
              children: <Widget>[
                ThemeOptionRow(), // Added const
                Divider(height: 1, thickness: 0.5),
                NotificationSettingRow(), // Added const
              ],
            ),
            const SizedBox(height: 24),
            const SettingsSectionHeader(title: "Data Management"),
            const SizedBox(height: 8),
            SettingsSectionContainer(
              children: <Widget>[
                provider_lib.Consumer3<CurrentStudentProfile, StudentSubjectsModel, TeacherSubjectsData>(
                  builder: (
                    BuildContext consumerContext,
                    CurrentStudentProfile currentStudentProfile,
                    StudentSubjectsModel studentSubjectsModel,
                    TeacherSubjectsData teacherSubjectsData,
                    Widget? child,
                  ) {
                    final String? studentRegNum =
                        currentStudentProfile.profile?.registerNumber;
                    final bool hasProfile = studentRegNum != null;

                    void showProfileRequiredSnackbar() {
                      ScaffoldMessenger.of(consumerContext).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Please set up your profile first to export attendance.',
                          ),
                          duration: Duration(seconds: 1, milliseconds: 500),
                        ),
                      );
                    }

                    return Column(
                      children: <Widget>[
                        // New: BackupRestoreRow for "Export General Attendance (CSV)" for student's own record
                        BackupRestoreRow(
                          icon: Icons.grid_on,
                          iconColor: Colors.purple.shade400,
                          title: "Export General Attendance (CSV)",
                          subtitle:
                              "Export your personal general attendance records.",
                          buttonText: "Export",
                          onPressed: hasProfile
                              ? () => DataManagementUtils
                                  .exportGeneralAttendance(
                                      consumerContext,
                                      forStudentRegisterNumber: studentRegNum,
                                    )
                              : showProfileRequiredSnackbar,
                        ),
                        const Divider(height: 1, thickness: 0.5),

                        BackupRestoreRow(
                          icon: Icons.article,
                          iconColor: Colors.teal.shade400,
                          title: "Export Subject Attendance (CSV)",
                          subtitle:
                              "Export your subject-specific attendance records.",
                          buttonText: "Export",
                          onPressed: hasProfile
                              ? () => DataManagementUtils
                                  .exportSubjectSpecificAttendance(
                                      consumerContext,
                                      forStudentRegisterNumber: studentRegNum,
                                    )
                              : showProfileRequiredSnackbar,
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 24),
            const SettingsSectionHeader(title: "Account Actions"),
            const SizedBox(height: 8),
            SettingsSectionContainer(
              children: <Widget>[
                provider_lib.Consumer<CurrentStudentProfile>(
                  builder: (
                    BuildContext context,
                    CurrentStudentProfile currentStudentProfile,
                    Widget? child,
                  ) {
                    final Student? currentStudent =
                        currentStudentProfile.profile;
                    return ListTile(
                      leading: Icon(
                        Icons.person_remove,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      title: const Text(
                        "Delete My Profile",
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                      subtitle: const Text(
                        "Permanently delete your student profile and all associated data.",
                      ),
                      onTap: currentStudent != null
                          ? () => _confirmRemoveStudentProfile(
                              context,
                              currentStudent,
                            )
                          : null,
                      enabled: currentStudent !=
                          null, // Disable if no profile exists
                      trailing: currentStudent == null
                          ? const Icon(
                              Icons.do_not_disturb_on_outlined,
                              color: Colors.grey,
                            )
                          : null,
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 26),

            const SizedBox(height: 8),

            const SizedBox(height: 26),
            Center(
              child: OutlinedButton.icon(
                onPressed: () {
                  // Reset user role to unselected and pop to RoleSelectionPage
                  provider_lib.Provider.of<UserSession>(
                    context,
                    listen: false,
                  ).userRole = UserRole.unselected;
                  Navigator.of(
                    context,
                  ).popUntil((route) => route.isFirst); // Go back to root page
                },
                icon: const Icon(Icons.logout),
                label: const Text('Change Role / Logout'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                  side: BorderSide(color: Theme.of(context).colorScheme.error),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  textStyle: const TextStyle(fontSize: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}