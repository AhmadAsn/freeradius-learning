<?php
// Test login flow
$h = getenv("MYSQL_HOST") ?: "db";
$p = getenv("MYSQL_PORT") ?: "3306";
$u = getenv("MYSQL_USER") ?: "radius";
$pw = getenv("MYSQL_PASSWORD") ?: "radius";
$db = getenv("MYSQL_DATABASE") ?: "radius";

echo "1. Testing mysqli connection...\n";
$conn = new mysqli($h, $u, $pw, $db, (int)$p);
if ($conn->connect_error) { echo "FAIL: " . $conn->connect_error . "\n"; exit(1); }
echo "   OK\n";

echo "2. Testing direct query...\n";
$result = $conn->query("SELECT id, username, password FROM operators WHERE username='administrator' AND password='radius'");
echo "   Rows found: " . $result->num_rows . "\n";
if ($result->num_rows > 0) {
    $row = $result->fetch_assoc();
    echo "   User: " . $row['username'] . " Password: " . $row['password'] . "\n";
}

echo "3. Testing PEAR DB connection...\n";
include_once('DB.php');
$dsn = sprintf("%s://%s:%s@%s:%s/%s", "mysqli", $u, $pw, $h, $p, $db);
echo "   DSN: " . $dsn . "\n";
$dbSocket = DB::connect($dsn);
if (DB::isError($dbSocket)) {
    echo "   PEAR DB FAIL: " . $dbSocket->getMessage() . "\n";
    exit(1);
}
echo "   PEAR DB OK\n";

echo "4. Testing PEAR DB query (same as dologin.php)...\n";
$operator_user = $dbSocket->escapeSimple('administrator');
$operator_pass = $dbSocket->escapeSimple('radius');
$sql = "SELECT * FROM operators WHERE username='$operator_user' AND password='$operator_pass'";
echo "   SQL: $sql\n";
$res = $dbSocket->query($sql);
$numRows = $res->numRows();
echo "   Rows found: $numRows\n";

if ($numRows === 1) {
    echo "   LOGIN WOULD SUCCEED!\n";
} else {
    echo "   LOGIN WOULD FAIL!\n";
}

$conn->close();
