package com.chiyeon.dangjik;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.net.InetAddress;
import java.net.UnknownHostException;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;

@RestController
public class DangjikController {

    // application.yml 의 server.instance-name (SERVER_NAME 환경변수로 주입) 값만 서버마다 다르게 준다.
    @Value("${server.instance-name:UNKNOWN}")
    private String instanceName;

    private static final DateTimeFormatter FORMATTER =
            DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

    @GetMapping(value = "/", produces = MediaType.TEXT_HTML_VALUE)
    public String index() {
        InfoData info = collectInfo();
        return """
                <!DOCTYPE html>
                <html lang="ko">
                <head>
                    <meta charset="UTF-8">
                    <title>Server Info</title>
                    <style>
                        body { font-family: -apple-system, sans-serif; background:#0f172a; color:#e2e8f0;
                               display:flex; align-items:center; justify-content:center; height:100vh; margin:0; }
                        .card { background:#1e293b; padding:40px 56px; border-radius:16px;
                                box-shadow:0 10px 30px rgba(0,0,0,0.4); text-align:center; }
                        h1 { font-size:2.2rem; margin:0 0 20px; color:#38bdf8; }
                        p { font-size:1.05rem; margin:6px 0; color:#cbd5e1; }
                        .label { color:#64748b; margin-right:8px; }
                    </style>
                </head>
                <body>
                    <div class="card">
                        <h1>%s 가 응답 중</h1>
                        <p><span class="label">Hostname:</span>%s</p>
                        <p><span class="label">IP:</span>%s</p>
                        <p><span class="label">응답 시각:</span>%s</p>
                    </div>
                </body>
                </html>
                """.formatted(info.name(), info.hostname(), info.ip(), info.time());
    }

    @GetMapping(value = "/api/info", produces = MediaType.APPLICATION_JSON_VALUE)
    public InfoData apiInfo() {
        return collectInfo();
    }

    private InfoData collectInfo() {
        String hostname;
        String ip;
        try {
            InetAddress addr = InetAddress.getLocalHost();
            hostname = addr.getHostName();
            ip = addr.getHostAddress();
        } catch (UnknownHostException e) {
            hostname = "unknown";
            ip = "unknown";
        }
        String time = LocalDateTime.now().format(FORMATTER);
        return new InfoData(instanceName, hostname, ip, time);
    }

    private record InfoData(String name, String hostname, String ip, String time) {
    }
}
