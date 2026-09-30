import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'app_database.dart';
import '../../utils/date_formatter.dart';

const _uuid = Uuid();

class DemoSeeder {
  static Future<void> seed(AppDatabase db) async {
    final now = DateTime.now();
    final nowMs = now.millisecondsSinceEpoch;
    final todayStr = DateFormatter.toIsoDateString(now);

    // 1. Settings
    final defaultSettings = {
      'school_name': 'Springfield Academy — Biometric Attendance',
      'student_cutoff_time': '08:30',
      'student_closing_time': '14:00',
      'attendance_grace_period': '15',
      'student_id_range_start': '1001',
      'student_id_range_end': '7999',
      'staff_id_range_start': '8001',
      'staff_id_range_end': '8999',
      'k50_ip': '192.168.18.78',
      'k50_port': '4370',
      'k50_bridge_port': '8787',
      'sms_enabled': 'true',
      'whatsapp_enabled': 'true',
      'twilio_account_sid': 'ACdemo92929948281818284828',
      'twilio_auth_token': 'demo_token_3992817294',
      'twilio_from_phone': '+15005550006',
      'twilio_whatsapp_from': 'whatsapp:+14155238886',
      'absence_sms_template':
          'Dear Parent, your child {student_name} is marked ABSENT today ({date}). Please contact school office if this is an error.',
      'absence_whatsapp_template':
          'Dear Parent, your child {student_name} is marked ABSENT today ({date}). Please contact school office if you need assistance.',
    };

    for (final entry in defaultSettings.entries) {
      await db.settingsDao.setSetting(entry.key, entry.value);
    }

    // 2. Staff & Users
    final adminHash = sha256.convert(utf8.encode('admin123')).toString();
    final staffHash = sha256.convert(utf8.encode('Staff123')).toString();

    final staffList = [
      {
        'name': 'System Administrator',
        'email': 'admin@school.local',
        'role': 'admin',
        'phone': '+15550000001',
        'staff_category': 'administrator',
        'employee_code': 'ADM001',
        'expected_start_time': '08:00',
        'grace_period': 15,
      },
      {
        'name': 'Dr. Robert Sterling',
        'email': 'principal@school.local',
        'role': 'principal',
        'phone': '+15550000002',
        'staff_category': 'administrator',
        'employee_code': 'ADM002',
        'expected_start_time': '08:00',
        'grace_period': 15,
      },
      {
        'name': 'Sarah Jenkins',
        'email': 'sarah.jenkins@school.local',
        'role': 'teacher',
        'phone': '+15550000003',
        'staff_category': 'teacher',
        'employee_code': 'TCH001',
        'expected_start_time': '08:00',
        'grace_period': 15,
      },
      {
        'name': 'Marcus Vance',
        'email': 'marcus.vance@school.local',
        'role': 'teacher',
        'phone': '+15550000004',
        'staff_category': 'teacher',
        'employee_code': 'TCH002',
        'expected_start_time': '08:00',
        'grace_period': 15,
      },
      {
        'name': 'Elena Rostova',
        'email': 'elena.rostova@school.local',
        'role': 'teacher',
        'phone': '+15550000005',
        'staff_category': 'teacher',
        'employee_code': 'TCH003',
        'expected_start_time': '08:15',
        'grace_period': 15,
      },
      {
        'name': 'David Kim',
        'email': 'david.kim@school.local',
        'role': 'teacher',
        'phone': '+15550000006',
        'staff_category': 'teacher',
        'employee_code': 'TCH004',
        'expected_start_time': '08:00',
        'grace_period': 15,
      },
      {
        'name': 'Arthur Pendelton',
        'email': 'arthur.p@school.local',
        'role': 'staff',
        'phone': '+15550000007',
        'staff_category': 'support_staff',
        'employee_code': 'STF001',
        'expected_start_time': '07:30',
        'grace_period': 15,
      },
      {
        'name': 'Maria Gomez',
        'email': 'maria.g@school.local',
        'role': 'staff',
        'phone': '+15550000008',
        'staff_category': 'support_staff',
        'employee_code': 'STF002',
        'expected_start_time': '07:45',
        'grace_period': 15,
      },
    ];

    final staffIds = <String, int>{};
    for (final s in staffList) {
      final code = s['employee_code'] as String;
      final existing = await db.staffDao.getStaffByEmployeeCode(code);
      if (existing != null) {
        staffIds[code] = existing.id;
      } else {
        final id = await db.staffDao.insertStaff(
          name: s['name'] as String,
          email: s['email'] as String,
          passwordHash: s['role'] == 'admin' ? adminHash : staffHash,
          role: s['role'] as String,
          phone: s['phone'] as String,
          staffCategory: s['staff_category'] as String,
          employeeCode: code,
          expectedStartTime: s['expected_start_time'] as String,
          gracePeriodMinutes: s['grace_period'] as int,
        );
        staffIds[code] = id;
      }
    }

    // 3. Classes and Sections
    final classesData = [
      {'name': 'Grade 1', 'numeric': 1, 'desc': 'First Grade Primary'},
      {'name': 'Grade 2', 'numeric': 2, 'desc': 'Second Grade Primary'},
      {'name': 'Grade 3', 'numeric': 3, 'desc': 'Third Grade Primary'},
      {'name': 'Grade 5', 'numeric': 5, 'desc': 'Fifth Grade Intermediate'},
      {'name': 'Grade 10', 'numeric': 10, 'desc': 'Tenth Grade Secondary'},
    ];

    final classIds = <String, int>{};
    final existingClasses = await db.classesDao.getAllClasses();
    for (final c in classesData) {
      final name = c['name'] as String;
      final existing = existingClasses.where((cl) => cl.name == name).firstOrNull;
      if (existing != null) {
        classIds[name] = existing.id;
      } else {
        final id = await db.classesDao.insertClass(
          name: name,
          numericGrade: c['numeric'] as int,
          description: c['desc'] as String,
        );
        classIds[name] = id;
      }
    }

    final sectionData = [
      {'class': 'Grade 1', 'name': 'Section 1-A', 'room': '101', 'cap': 30},
      {'class': 'Grade 1', 'name': 'Section 1-B', 'room': '102', 'cap': 30},
      {'class': 'Grade 2', 'name': 'Section 2-A', 'room': '201', 'cap': 30},
      {'class': 'Grade 3', 'name': 'Section 3-A', 'room': '301', 'cap': 30},
      {'class': 'Grade 5', 'name': 'Section 5-A', 'room': '501', 'cap': 35},
      {'class': 'Grade 10', 'name': 'Section 10-A', 'room': '1001', 'cap': 35},
    ];

    final sectionIds = <String, int>{};
    for (final s in sectionData) {
      final className = s['class'] as String;
      final name = s['name'] as String;
      final cId = classIds[className]!;
      final existingSections = await db.sectionsDao.getSectionsByClassId(cId);
      final existing = existingSections.where((sec) => sec.name == name).firstOrNull;
      if (existing != null) {
        sectionIds[name] = existing.id;
      } else {
        final id = await db.sectionsDao.insertSection(
          classId: cId,
          name: name,
          roomNumber: s['room'] as String,
          capacity: s['cap'] as int,
        );
        sectionIds[name] = id;
      }
    }

    // 4. Students
    final studentsData = [
      {
        'code': 'STU-1001',
        'name': 'Liam Walker',
        'gender': 'male',
        'parent': 'James Walker',
        'phone': '+15551234001',
        'class': 'Grade 1',
        'sec': 'Section 1-A',
        'roll': '01',
      },
      {
        'code': 'STU-1002',
        'name': 'Emma Johnson',
        'gender': 'female',
        'parent': 'Laura Johnson',
        'phone': '+15551234002',
        'class': 'Grade 1',
        'sec': 'Section 1-A',
        'roll': '02',
      },
      {
        'code': 'STU-1003',
        'name': 'Noah Smith',
        'gender': 'male',
        'parent': 'Michael Smith',
        'phone': '+15551234003',
        'class': 'Grade 1',
        'sec': 'Section 1-A',
        'roll': '03',
      },
      {
        'code': 'STU-1004',
        'name': 'Olivia Brown',
        'gender': 'female',
        'parent': 'Sarah Brown',
        'phone': '+15551234004',
        'class': 'Grade 1',
        'sec': 'Section 1-B',
        'roll': '01',
      },
      {
        'code': 'STU-1005',
        'name': 'William Davis',
        'gender': 'male',
        'parent': 'Robert Davis',
        'phone': '+15551234005',
        'class': 'Grade 1',
        'sec': 'Section 1-B',
        'roll': '02',
      },
      {
        'code': 'STU-1006',
        'name': 'Ava Miller',
        'gender': 'female',
        'parent': 'Jennifer Miller',
        'phone': '+15551234006',
        'class': 'Grade 2',
        'sec': 'Section 2-A',
        'roll': '01',
      },
      {
        'code': 'STU-1007',
        'name': 'James Wilson',
        'gender': 'male',
        'parent': 'David Wilson',
        'phone': '+15551234007',
        'class': 'Grade 2',
        'sec': 'Section 2-A',
        'roll': '02',
      },
      {
        'code': 'STU-1008',
        'name': 'Sophia Martinez',
        'gender': 'female',
        'parent': 'Carlos Martinez',
        'phone': '+15551234008',
        'class': 'Grade 3',
        'sec': 'Section 3-A',
        'roll': '01',
      },
      {
        'code': 'STU-1009',
        'name': 'Benjamin Taylor',
        'gender': 'male',
        'parent': 'Karen Taylor',
        'phone': '+15551234009',
        'class': 'Grade 3',
        'sec': 'Section 3-A',
        'roll': '02',
      },
      {
        'code': 'STU-1010',
        'name': 'Mia Anderson',
        'gender': 'female',
        'parent': 'Thomas Anderson',
        'phone': '+15551234010',
        'class': 'Grade 5',
        'sec': 'Section 5-A',
        'roll': '01',
      },
      {
        'code': 'STU-1011',
        'name': 'Lucas Thomas',
        'gender': 'male',
        'parent': 'Nancy Thomas',
        'phone': '+15551234011',
        'class': 'Grade 5',
        'sec': 'Section 5-A',
        'roll': '02',
      },
      {
        'code': 'STU-1012',
        'name': 'Charlotte Jackson',
        'gender': 'female',
        'parent': 'Paul Jackson',
        'phone': '+15551234012',
        'class': 'Grade 10',
        'sec': 'Section 10-A',
        'roll': '01',
      },
      {
        'code': 'STU-1013',
        'name': 'Mason White',
        'gender': 'male',
        'parent': 'Emily White',
        'phone': '+15551234013',
        'class': 'Grade 10',
        'sec': 'Section 10-A',
        'roll': '02',
      },
      {
        'code': 'STU-1014',
        'name': 'Harper Harris',
        'gender': 'female',
        'parent': 'Brian Harris',
        'phone': '+15551234014',
        'class': 'Grade 10',
        'sec': 'Section 10-A',
        'roll': '03',
      },
      {
        'code': 'STU-1015',
        'name': 'Ethan Clark',
        'gender': 'male',
        'parent': 'George Clark',
        'phone': '+15551234015',
        'class': 'Grade 1',
        'sec': 'Section 1-A',
        'roll': '04',
      },
      {
        'code': 'STU-1016',
        'name': 'Amelia Lewis',
        'gender': 'female',
        'parent': 'Susan Lewis',
        'phone': '+15551234016',
        'class': 'Grade 2',
        'sec': 'Section 2-A',
        'roll': '03',
      },
    ];

    final studentIds = <String, int>{};
    for (final stu in studentsData) {
      final code = stu['code'] as String;
      final existing = await db.studentsDao.getStudentByCode(code);
      int sId;
      if (existing != null) {
        sId = existing.id;
      } else {
        sId = await db.studentsDao.insertStudent(
          studentCode: code,
          name: stu['name'] as String,
          gender: stu['gender'] as String,
          parentName: stu['parent'] as String,
          parentPhone: stu['phone'] as String,
          whatsappPhone: stu['phone'] as String,
          notificationOptIn: 1,
        );
      }
      studentIds[code] = sId;

      final cName = stu['class'] as String;
      final sName = stu['sec'] as String;
      final cId = classIds[cName]!;
      final secId = sectionIds[sName]!;
      final existingEnrollment = await db.customSelect(
        "SELECT id FROM student_enrollments WHERE student_id = ? AND status = 'active'",
        variables: [Variable(sId)],
      ).get();

      if (existingEnrollment.isEmpty) {
        await db.enrollmentsDao.enrollStudent(
          studentId: sId,
          classId: cId,
          sectionId: secId,
          academicYear: '2026-2027',
          rollNumber: stu['roll'] as String,
        );
      }
    }

    // 5. Today's Student Attendance
    DateTime makeTime(int hour, int minute) =>
        DateTime(now.year, now.month, now.day, hour, minute);

    final studentAttendanceData = [
      {'code': 'STU-1001', 'status': 'present', 'time': makeTime(7, 55)},
      {'code': 'STU-1002', 'status': 'present', 'time': makeTime(8, 2)},
      {'code': 'STU-1003', 'status': 'late', 'time': makeTime(8, 35)},
      {'code': 'STU-1004', 'status': 'present', 'time': makeTime(8, 10)},
      {'code': 'STU-1005', 'status': 'absent', 'time': null},
      {'code': 'STU-1006', 'status': 'present', 'time': makeTime(8, 0)},
      {'code': 'STU-1007', 'status': 'absent', 'time': null},
      {'code': 'STU-1008', 'status': 'present', 'time': makeTime(7, 50)},
      {'code': 'STU-1009', 'status': 'late', 'time': makeTime(8, 42)},
      {'code': 'STU-1010', 'status': 'present', 'time': makeTime(8, 5)},
      {'code': 'STU-1011', 'status': 'absent', 'time': null},
      {'code': 'STU-1012', 'status': 'present', 'time': makeTime(7, 48)},
      {'code': 'STU-1013', 'status': 'present', 'time': makeTime(8, 12)},
      {'code': 'STU-1014', 'status': 'present', 'time': makeTime(8, 15)},
      {'code': 'STU-1015', 'status': 'present', 'time': makeTime(8, 8)},
      {'code': 'STU-1016', 'status': 'present', 'time': makeTime(7, 59)},
    ];

    for (final att in studentAttendanceData) {
      final code = att['code'] as String;
      final sId = studentIds[code];
      if (sId == null) continue;

      final time = att['time'] as DateTime?;
      final status = att['status'] as String;

      await db.attendanceDao.insertOrUpdateAttendance(
        personType: 'student',
        studentId: sId,
        date: todayStr,
        checkInTime: time?.millisecondsSinceEpoch,
        status: status,
        method: time != null ? 'fingerprint' : 'auto_cutoff',
        notes: status == 'absent' ? 'Unexcused absence - auto cutoff' : null,
      );
    }

    // 6. Today's Staff Attendance
    final staffAttendanceData = [
      {
        'code': 'ADM002',
        'in': makeTime(7, 45),
        'out': null,
        'status': 'present'
      },
      {
        'code': 'TCH001',
        'in': makeTime(7, 50),
        'out': null,
        'status': 'present'
      },
      {'code': 'TCH002', 'in': makeTime(8, 22), 'out': null, 'status': 'late'},
      {
        'code': 'TCH003',
        'in': makeTime(8, 10),
        'out': null,
        'status': 'present'
      },
      {
        'code': 'TCH004',
        'in': makeTime(7, 55),
        'out': null,
        'status': 'present'
      },
      {
        'code': 'STF001',
        'in': makeTime(7, 25),
        'out': makeTime(16, 0),
        'status': 'present'
      },
      {
        'code': 'STF002',
        'in': makeTime(7, 40),
        'out': makeTime(16, 30),
        'status': 'present'
      },
    ];

    for (final att in staffAttendanceData) {
      final code = att['code'] as String;
      final uId = staffIds[code];
      if (uId == null) continue;

      final inTime = att['in'] as DateTime?;
      final outTime = att['out'] as DateTime?;
      final status = att['status'] as String;

      await db.attendanceDao.insertOrUpdateAttendance(
        personType: 'staff',
        staffId: uId,
        date: todayStr,
        checkInTime: inTime?.millisecondsSinceEpoch,
        checkOutTime: outTime?.millisecondsSinceEpoch,
        status: status,
        method: 'fingerprint',
      );
    }

    // 7. Parent Notification Jobs (for absent students)
    final absentStudents = [
      {
        'code': 'STU-1005',
        'name': 'William Davis',
        'phone': '+15551234005',
        'channel': 'sms',
        'status': 'sent'
      },
      {
        'code': 'STU-1005',
        'name': 'William Davis',
        'phone': '+15551234005',
        'channel': 'whatsapp',
        'status': 'sent'
      },
      {
        'code': 'STU-1007',
        'name': 'James Wilson',
        'phone': '+15551234007',
        'channel': 'sms',
        'status': 'sent'
      },
      {
        'code': 'STU-1011',
        'name': 'Lucas Thomas',
        'phone': '+15551234011',
        'channel': 'sms',
        'status': 'pending'
      },
      {
        'code': 'STU-1011',
        'name': 'Lucas Thomas',
        'phone': '+15551234011',
        'channel': 'whatsapp',
        'status': 'pending'
      },
    ];

    for (final job in absentStudents) {
      final sId = studentIds[job['code']]!;
      final sName = job['name'] as String;
      final phone = job['phone'] as String;
      final channel = job['channel'] as String;
      final status = job['status'] as String;

      final message =
          'Dear Parent, your child $sName is marked ABSENT today ($todayStr). Please contact school office if this is an error.';

      final jobId = await db.notificationsDao.createJob(
        studentId: sId,
        date: todayStr,
        channel: channel,
        recipientPhone: phone,
        message: message,
      );

      if (status == 'sent') {
        await db.notificationsDao.updateJobStatus(
          jobId,
          'sent',
          sentAt: nowMs - 1200000,
        );
        await db.notificationsDao.recordAttempt(
          jobId: jobId,
          attemptNumber: 1,
          provider: 'twilio',
          status: 'success',
          providerMessageId: 'SM${_uuid.v4().replaceAll('-', '').substring(0, 32)}',
          responseBody: '{"status":"delivered","sid":"SMdemo"}',
        );
      }
    }

    // 8. Activity Logs
    await db.activityDao.log(
      entityType: 'system',
      entityId: '0',
      action: 'seed_demo_data',
      details: 'Populated full school demo roster with 16 students, 8 staff, classes, today attendance, and parent alerts.',
    );
    await db.activityDao.log(
      entityType: 'attendance',
      entityId: 'STU-1001',
      action: 'biometric_check_in',
      details: 'Liam Walker (Grade 1-A) scanned fingerprint at 07:55 AM on K50 Device #1',
    );
    await db.activityDao.log(
      entityType: 'attendance',
      entityId: 'TCH001',
      action: 'biometric_check_in',
      details: 'Sarah Jenkins (Math Teacher) scanned fingerprint at 07:50 AM on K50 Device #1',
    );
    await db.activityDao.log(
      entityType: 'notification',
      entityId: 'JOB-SMS',
      action: 'parent_alert_sent',
      details: 'Twilio SMS sent to +15551234005 for William Davis unexcused absence.',
    );
  }

  /// Seeds only standard system settings and the primary administrator account.
  /// Leaves students, classes, sections, and attendances completely clean for production.
  static Future<void> seedDefaultsOnly(AppDatabase db) async {
    final defaultSettings = {
      'school_name': 'School Attendance Portal',
      'student_cutoff_time': '08:30',
      'student_closing_time': '14:00',
      'attendance_grace_period': '15',
      'student_id_range_start': '1001',
      'student_id_range_end': '7999',
      'staff_id_range_start': '8001',
      'staff_id_range_end': '8999',
      'k50_ip': '192.168.18.78',
      'k50_port': '4370',
      'k50_bridge_port': '8787',
      'sms_enabled': 'true',
      'whatsapp_enabled': 'true',
      'twilio_account_sid': '',
      'twilio_auth_token': '',
      'twilio_from_phone': '',
      'twilio_whatsapp_from': '',
      'absence_sms_template':
          'Dear Parent, your child {student_name} is marked ABSENT today ({date}). Please contact school office if this is an error.',
      'absence_whatsapp_template':
          'Dear Parent, your child {student_name} is marked ABSENT today ({date}). Please contact school office if you need assistance.',
    };

    for (final entry in defaultSettings.entries) {
      final existing = await db.settingsDao.getSetting(entry.key);
      if (existing.isEmpty) {
        await db.settingsDao.setSetting(entry.key, entry.value);
      }
    }

    final adminHash = sha256.convert(utf8.encode('admin123')).toString();

    final existingAdmin = await db.staffDao.getStaffByEmployeeCode('ADM001');
    if (existingAdmin == null) {
      await db.staffDao.insertStaff(
        name: 'System Administrator',
        email: 'admin@school.local',
        passwordHash: adminHash,
        role: 'admin',
        phone: '+15550000001',
        staffCategory: 'administrator',
        employeeCode: 'ADM001',
        expectedStartTime: '08:00',
        gracePeriodMinutes: 15,
      );
    }
  }


  static const demoStudentCodes = [
    'STU-1001', 'STU-1002', 'STU-1003', 'STU-1004',
    'STU-1005', 'STU-1006', 'STU-1007', 'STU-1008',
    'STU-1009', 'STU-1010', 'STU-1011', 'STU-1012',
    'STU-1013', 'STU-1014', 'STU-1015', 'STU-1016',
  ];

  static const demoStaffCodes = [
    'ADM002', 'TCH001', 'TCH002', 'TCH003', 'TCH004', 'STF001', 'STF002',
  ];

  /// Removes ONLY the dummy/sample students, dummy staff, and their sample attendance records.
  /// ALL user-created students (like Abdullah, etc.), user-created staff, and real attendance punches are strictly PRESERVED.
  static Future<int> clearDummyData(AppDatabase db) async {
    final quotedCodes = demoStudentCodes.map((c) => "'$c'").join(',');
    final quotedStaff = demoStaffCodes.map((c) => "'$c'").join(',');

    // 1. Delete notifications for demo students
    await db.customStatement('''
      DELETE FROM notification_delivery_attempts
      WHERE job_id IN (
        SELECT id FROM parent_notification_jobs
        WHERE student_id IN (SELECT id FROM students WHERE student_code IN ($quotedCodes))
      );
    ''');
    await db.customStatement('''
      DELETE FROM parent_notification_jobs
      WHERE student_id IN (SELECT id FROM students WHERE student_code IN ($quotedCodes));
    ''');

    // 2. Delete attendances for demo students and demo staff
    await db.customStatement('''
      DELETE FROM school_attendances
      WHERE student_id IN (SELECT id FROM students WHERE student_code IN ($quotedCodes));
    ''');
    await db.customStatement('''
      DELETE FROM school_attendances
      WHERE staff_id IN (SELECT id FROM users WHERE employee_code IN ($quotedStaff));
    ''');

    // 3. Delete enrollments for demo students
    await db.customStatement('''
      DELETE FROM student_enrollments
      WHERE student_id IN (SELECT id FROM students WHERE student_code IN ($quotedCodes));
    ''');

    // 4. Delete demo students
    final deletedStudents = await db.customSelect(
      'SELECT COUNT(*) AS c FROM students WHERE student_code IN ($quotedCodes);',
    ).getSingle();
    final studentCount = deletedStudents.read<int>('c');

    await db.customStatement('DELETE FROM students WHERE student_code IN ($quotedCodes);');

    // 5. Delete demo staff (keep admin ADM001 and all user-created staff)
    await db.customStatement('DELETE FROM users WHERE employee_code IN ($quotedStaff);');

    // NOTE: NEVER delete school_classes or sections!
    // School classes and sections (e.g. Class 10, Section B) are structural configurations
    // set up by the school administrator. They must be preserved across dummy data purges.

    // 7. Remove demo seeder activity logs
    await db.customStatement('''
      DELETE FROM activity_logs
      WHERE action = 'seed_demo_data'
         OR details LIKE '%Liam Walker%'
         OR details LIKE '%Sarah Jenkins%'
         OR details LIKE '%William Davis%';
    ''');

    await db.activityDao.log(
      entityType: 'system',
      entityId: '0',
      action: 'purge_demo_data',
      details: 'Removed $studentCount demo students and sample staff. Real students and records preserved.',
    );

    return studentCount;
  }

  /// Full factory reset: wipes everything and restores clean default admin & settings.
  static Future<void> factoryReset(AppDatabase db) async {
    await db.customStatement('DELETE FROM notification_delivery_attempts;');
    await db.customStatement('DELETE FROM parent_notification_jobs;');
    await db.customStatement('DELETE FROM school_attendances;');
    await db.customStatement('DELETE FROM student_enrollments;');
    await db.customStatement('DELETE FROM students;');
    await db.customStatement('DELETE FROM sections;');
    await db.customStatement('DELETE FROM school_classes;');
    await db.customStatement('DELETE FROM users;');
    await db.customStatement('DELETE FROM activity_logs;');
    await seedDefaultsOnly(db);
  }
}
