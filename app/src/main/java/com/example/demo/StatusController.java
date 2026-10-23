package com.example.demo;

import jakarta.annotation.PostConstruct;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.time.Duration;
import java.util.HashMap;
import java.util.Map;
import java.util.Random;

@RestController
@RequestMapping("/api")
public class StatusController {

    private static final Logger logger = LoggerFactory.getLogger(StatusController.class);
    private final StringRedisTemplate redis;
    private final Random random = new Random();

    @Value("${SUCCESS_RATE:0.3}")
    private double successRate;
    @Value("${LATENCY_RATE:0.3}")
    private double latencyRate;
    @Value("${GIT_COMMIT:unknown}")
    private String gitCommit;
    @Value("${DEPLOY_ID:unknown}")
    private String deployId;

    private String serviceVersion;
    private static final String REDIS_KEY_PREFIX = "latency_test_key";

    public StatusController(StringRedisTemplate redis) {
        this.redis = redis;
    }

    @PostConstruct
    public void init() {
        String otelAttrs = System.getenv("OTEL_RESOURCE_ATTRIBUTES");
        this.serviceVersion = parseOtelResourceAttributes(otelAttrs).getOrDefault("service.version", "1.0.0");
        logger.info("Server started on port 80 (service.version={})", serviceVersion);
    }

    @GetMapping("/status")
    public ResponseEntity<Map<String, Object>> getStatus() {
        long start = System.currentTimeMillis();
        String behavior = serviceVersion.startsWith("2") ? "v2" : "v1";

        String outcome = "UNKNOWN";
        int statusCode = 200;
        String message = "Status check complete.";

        logger.info("API Hit: service_version={}, behavior={}", serviceVersion, behavior);

        if ("v1".equals(behavior)) {
            outcome = "SUCCESS";
            runRedisSet(); 
        } else {
            double r = random.nextDouble();

            if (r < successRate) {
                outcome = "SUCCESS";
                runRedisSet();
            } 
            else if (r < successRate + latencyRate) {
                outcome = "LATENCY";
                simulateLatency();
                message = "Redis access slow down";
            }
            else {
                outcome = "ERROR";
                simulateRedisLoad();
            }
        }

        return buildResponse(statusCode, outcome, message, start);
    }

    // --- otel.instrumentation.methods.include で Span 化する対象 ---

    public void runRedisSet() {
        try {
            redis.opsForValue().set("status_key", "ok", Duration.ofSeconds(60));
        } catch (Exception e) {
            logger.warn("Redis operation failed: {}", e.getMessage());
        }
    }

    public void simulateLatency() {
        logger.warn("Slow Response Simulation");
        for (int i = 0; i < 100; i++) {
            try {
                redis.opsForValue().set(REDIS_KEY_PREFIX + ":" + i, "latency_data", Duration.ofSeconds(60));
            } catch (Exception e) {
                logger.warn("Redis operation failed during latency simulation: {}", e.getMessage());
            }
        }
    }

    public void simulateRedisLoad() {
        logger.warn("Redis connection failure. Can't reach Redis server.");
        throw new RuntimeException("Could not connect to Redis: Connection refused");
    }

    // --- Helpers ---

    private Map<String, String> parseOtelResourceAttributes(String attrStr) {
        Map<String, String> map = new HashMap<>();
        if (attrStr == null || attrStr.isEmpty()) return map;
        for (String pair : attrStr.split(",")) {
            String[] kv = pair.split("=");
            if (kv.length == 2) map.put(kv[0].trim(), kv[1].trim());
        }
        return map;
    }

    private ResponseEntity<Map<String, Object>> buildResponse(int status, String outcome, String message, long startTime) {
        Map<String, Object> body = new HashMap<>();
        body.put("timestamp", System.currentTimeMillis());
        body.put("outcome", outcome);
        body.put("latency_ms", System.currentTimeMillis() - startTime);
        body.put("service_version", serviceVersion);
        body.put("commit", gitCommit);
        body.put("deploy", deployId);
        
        if (status >= 400) {
            body.put("error", message);
        } else {
            body.put("message", message);
            body.put("redis_active", true);
        }
        return ResponseEntity.status(status).body(body);
    }
}
