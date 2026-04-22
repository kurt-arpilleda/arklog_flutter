<?php
include "../kurt_dbConn.php";
header('Content-Type: application/json');

if (!$db) {
    die(json_encode(["success" => false, "message" => "Database connection failed"]));
}

$idNumber = isset($_POST['idNumber']) ? trim($_POST['idNumber']) : '';
$presentAddress = isset($_POST['presentAddress']) ? trim($_POST['presentAddress']) : '';
$modeOfTransportation = isset($_POST['modeOfTransportation']) ? trim($_POST['modeOfTransportation']) : '';

if ($idNumber === '' || $presentAddress === '' || $modeOfTransportation === '') {
    die(json_encode(["success" => false, "message" => "Missing required fields"]));
}

if (!is_numeric($modeOfTransportation)) {
    die(json_encode(["success" => false, "message" => "Invalid mode of transportation"]));
}

$modeValue = (int)$modeOfTransportation;
if ($modeValue < 0 || $modeValue > 2) {
    die(json_encode(["success" => false, "message" => "Invalid mode of transportation"]));
}

$employeeQuery = "
    SELECT
        e.idNumber,
        CONCAT(e.firstName, ' ', e.surName) AS employeeName,
        d.departmentName,
        s.sectionName
    FROM hr_employee e
    LEFT JOIN hr_department d ON e.departmentId = d.departmentId
    LEFT JOIN ppic_section s ON e.sectionId = s.sectionId
    WHERE e.idNumber = ?
    LIMIT 1
";

$employeeStmt = $db->prepare($employeeQuery);
if (!$employeeStmt) {
    die(json_encode(["success" => false, "message" => "Failed to prepare employee query"]));
}

$employeeStmt->bind_param("s", $idNumber);
$employeeStmt->execute();
$employeeResult = $employeeStmt->get_result();

if (!$employeeResult || $employeeResult->num_rows === 0) {
    $employeeStmt->close();
    die(json_encode(["success" => false, "message" => "Employee not found"]));
}

$employeeRow = $employeeResult->fetch_assoc();
$employeeStmt->close();

$employeeId = $employeeRow['idNumber'];
$employeeName = $employeeRow['employeeName'];
$department = $employeeRow['departmentName'];
$section = $employeeRow['sectionName'];

$insertQuery = "
    INSERT INTO hr_transposupportsurvey
    (employeeId, employeeName, department, section, presentAddress, modeOfTransportation)
    VALUES (?, ?, ?, ?, ?, ?)
";

$insertStmt = $db->prepare($insertQuery);
if (!$insertStmt) {
    die(json_encode(["success" => false, "message" => "Failed to prepare insert query"]));
}

$insertStmt->bind_param("sssssi", $employeeId, $employeeName, $department, $section, $presentAddress, $modeValue);
$insertSuccess = $insertStmt->execute();
$insertStmt->close();
$db->close();

if ($insertSuccess) {
    echo json_encode(["success" => true, "message" => "Survey submitted successfully"]);
} else {
    echo json_encode(["success" => false, "message" => "Failed to submit survey"]);
}
?>
