<?php
$servername = "mysql";
$username = "root";
$password = "Passw0rd";

// Create connection
$conn = new mysqli($servername, $username, $password);

// Check connection
if ($conn->connect_error) {
    die("连接错误: " . $conn->connect_error);
}
echo "<h1>成功连接 MySQL 服务器</h1>";

phpinfo();

?>
