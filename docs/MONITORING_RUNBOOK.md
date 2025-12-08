# Monitoring Runbook

This runbook provides step-by-step procedures for handling common alerts in the microservices monitoring setup. It covers Prometheus alerts related to high error rates, pod crashes, scaling issues, and performance degradation.

---

## Alert Categories

1. [Application Errors](#application-errors)
2. [Pod Crashes & Restarts](#pod-crashes--restarts)
3. [Resource Scaling & Capacity](#resource-scaling--capacity)
4. [Performance Degradation](#performance-degradation)
5. [Infrastructure Issues](#infrastructure-issues)

---

## Application Errors

### Alert: HighErrorRate (event-service, user-service, booking-service, search-service)

**Severity:** Warning / Critical  
**Threshold:** > 1 error request/sec (5xx) for 5 minutes

#### Symptoms
- Grafana shows spike in HTTP 5xx responses
- Alertmanager notification received
- Application logs show exceptions or stack traces

#### Investigation Steps

1. **Check real-time logs:**
   ```powershell
   # Example for event-service
   kubectl logs -n default deployment/event-service -f --tail=100
   ```

2. **Verify service is running:**
   ```powershell
   kubectl get pods -n default | grep event-service
   kubectl describe pod -n default <pod-name>
   ```

3. **Check recent deployments:**
   ```powershell
   kubectl rollout history deployment/event-service -n default
   kubectl rollout status deployment/event-service -n default
   ```

4. **Inspect Prometheus metrics:**
   - Open Prometheus UI (port-forward or ingress)
   - Query: `rate(http_requests_total{app="event-service",status=~"5.."}[5m])`
   - Check which endpoints are returning errors

#### Resolution

**Option A: Restart the service**
```powershell
kubectl rollout restart deployment/event-service -n default
```

**Option B: Rollback if recently deployed**
```powershell
kubectl rollout undo deployment/event-service -n default
kubectl rollout status deployment/event-service -n default
```

**Option C: Scale down and up (if suspected resource contention)**
```powershell
kubectl scale deployment event-service --replicas=0 -n default
Start-Sleep -Seconds 10
kubectl scale deployment event-service --replicas=2 -n default
```

**Option D: Check dependency services**
- Verify database connectivity
- Check if other microservices are reachable
- Validate API keys and secrets in configmaps

#### Prevention

- Add health checks to deployments
- Implement circuit breakers in service code
- Enable graceful shutdown with preStop hooks

---

## Pod Crashes & Restarts

### Alert: PodCrashLooping

**Severity:** Critical  
**Threshold:** Pod restarting multiple times in 15 minutes

#### Symptoms
- Pod shows status `CrashLoopBackOff`
- Container restart count > 3 in 10 minutes
- Application unable to start

#### Investigation Steps

1. **Examine pod events and logs:**
   ```powershell
   kubectl describe pod -n default <pod-name>
   kubectl logs -n default <pod-name> --previous
   kubectl logs -n default <pod-name> --all-containers=true
   ```

2. **Check resource requests/limits:**
   ```powershell
   kubectl get pod -n default <pod-name> -o yaml | grep -A 10 "resources:"
   ```

3. **Verify dependencies are available:**
   ```powershell
   # Check if database is reachable
   kubectl exec -n default <pod-name> -- sh -c "nc -zv postgres-db 5432"
   ```

4. **Check configuration:**
   ```powershell
   kubectl get configmap -n default
   kubectl get secret -n default
   ```

#### Resolution

**Option A: Check logs for configuration errors**
```powershell
# Get full log output
kubectl logs -n default <pod-name> --previous
```

**Option B: Increase resource limits if OOMKilled**
```powershell
# Edit deployment and increase memory
kubectl set resources deployment/<service-name> -n default --limits=memory=1Gi
```

**Option C: Fix missing environment variables**
```powershell
# Verify all expected env vars are set
kubectl exec -n default <pod-name> -- env | sort
```

**Option D: Restart with exponential backoff**
```powershell
# Delete pod to trigger new creation
kubectl delete pod -n default <pod-name>
```

#### Prevention

- Run liveness and readiness probes
- Test configuration before deploying
- Use init containers to verify dependencies
- Set appropriate resource requests

---

## Resource Scaling & Capacity

### Alert: HighMemoryUsage

**Severity:** Warning  
**Threshold:** Memory usage > 80% of limit

#### Symptoms
- Pod memory climbing over time
- Potential memory leak suspected
- Application performance degradation

#### Investigation Steps

1. **Check current memory usage:**
   ```powershell
   kubectl top pod -n default
   kubectl top nodes
   ```

2. **View memory trend in Prometheus:**
   - Query: `container_memory_usage_bytes{pod=~"event-service.*"}`
   - Query: `container_memory_limit_bytes{pod=~"event-service.*"}`

3. **Identify memory leaks:**
   ```powershell
   # Check if memory stabilizes after restart
   kubectl logs -n default <pod-name> | grep -i "alloc\|heap"
   ```

#### Resolution

**Option A: Increase memory limit**
```powershell
kubectl set resources deployment/event-service -n default --limits=memory=2Gi --requests=memory=1Gi
```

**Option B: Scale up replicas to distribute load**
```powershell
kubectl scale deployment/event-service --replicas=3 -n default
```

**Option C: Identify and fix memory leak in code**
- Review recent code changes
- Profile application using pprof (Go) or heap dumps (Java)
- Deploy patched version

#### Prevention

- Set resource requests and limits
- Implement memory profiling in CI/CD
- Monitor memory trends proactively

---

### Alert: HighCPUUsage

**Severity:** Warning  
**Threshold:** CPU usage > 80% of limit for 5 minutes

#### Symptoms
- High CPU utilization across multiple pods
- Slow API response times
- Increased latency in services

#### Investigation Steps

1. **Check CPU metrics:**
   ```powershell
   kubectl top pod -n default
   ```

2. **Query Prometheus for hot spots:**
   - Query: `rate(container_cpu_usage_seconds_total{pod=~"event-service.*"}[5m])`
   - Identify which containers are consuming CPU

3. **Profile the application:**
   ```powershell
   # For Go services (pprof)
   kubectl port-forward -n default <pod-name> 6060:6060
   # Visit http://localhost:6060/debug/pprof
   ```

#### Resolution

**Option A: Scale horizontally**
```powershell
kubectl scale deployment/event-service --replicas=4 -n default
```

**Option B: Optimize code (slow queries, loops)**
- Review application profiling data
- Optimize expensive operations
- Deploy fixed version

**Option C: Adjust CPU limits**
```powershell
kubectl set resources deployment/event-service -n default --limits=cpu=1000m --requests=cpu=500m
```

#### Prevention

- Set CPU resource requests appropriate to workload
- Implement query caching
- Use database indexes
- Load test before production deployment

---

## Performance Degradation

### Alert: HighLatency

**Severity:** Warning  
**Threshold:** p99 response time > 1 second

#### Symptoms
- Users report slow API responses
- Prometheus latency metrics increasing
- High request queue depth

#### Investigation Steps

1. **Check latency metrics:**
   - Query: `histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m]))`

2. **Identify slow endpoints:**
   - Query: `http_request_duration_seconds_sum{job="event-service"} / http_request_duration_seconds_count{job="event-service"}`

3. **Check database query performance:**
   ```powershell
   kubectl logs -n default <pod-name> | grep -i "slow query\|duration"
   ```

4. **Verify downstream services:**
   - Check if dependent services are responsive
   - Verify network connectivity

#### Resolution

**Option A: Scale up problematic service**
```powershell
kubectl scale deployment/event-service --replicas=3 -n default
```

**Option B: Clear caches if applicable**
```powershell
# Connect to Redis/cache and flush
kubectl exec -n default <cache-pod> -- redis-cli FLUSHDB
```

**Option C: Identify and optimize slow queries**
- Review database logs
- Add indexes to frequently queried columns
- Optimize application code

#### Prevention

- Implement query result caching
- Add database connection pooling
- Monitor slow query logs
- Conduct regular performance testing

---

## Infrastructure Issues

### Alert: NodeNotReady

**Severity:** Critical  
**Threshold:** Node in NotReady state for > 5 minutes

#### Symptoms
- Node status shows `NotReady` or `SchedulingDisabled`
- Pods on node pending/terminating
- Cluster capacity reduced

#### Investigation Steps

1. **Check node status:**
   ```powershell
   kubectl get nodes -o wide
   kubectl describe node <node-name>
   ```

2. **Check node conditions:**
   ```powershell
   kubectl get nodes -o custom-columns=NAME:.metadata.name,STATUS:.status.conditions[*].type,MESSAGE:.status.conditions[*].message
   ```

3. **SSH to node and check system resources:**
   ```bash
   df -h              # Disk space
   free -h            # Memory
   top                # Process list
   dmesg | tail -20   # Kernel logs
   ```

#### Resolution

**Option A: Cordon and drain node**
```powershell
kubectl cordon <node-name>
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data
```

**Option B: Restart node (AWS EC2)**
```powershell
# Via AWS CLI or console, terminate the instance
# EKS will auto-scale and launch replacement
aws ec2 reboot-instances --instance-ids <instance-id>
```

**Option C: Uncordon node after recovery**
```powershell
kubectl uncordon <node-name>
```

#### Prevention

- Monitor disk space usage regularly
- Set up node auto-repair policies in EKS
- Configure cluster autoscaler
- Implement pod disruption budgets

---

### Alert: PersistentVolumePending

**Severity:** Warning  
**Threshold:** PVC in Pending state for > 10 minutes

#### Symptoms
- Pod cannot mount volume
- Pod stuck in Pending state
- Storage provisioning failed

#### Investigation Steps

1. **Check PVC status:**
   ```powershell
   kubectl get pvc -n default
   kubectl describe pvc -n default <pvc-name>
   ```

2. **Check storage class:**
   ```powershell
   kubectl get storageclass
   kubectl describe storageclass <storage-class-name>
   ```

3. **Check events:**
   ```powershell
   kubectl get events -n default --sort-by='.lastTimestamp' | tail -20
   ```

#### Resolution

**Option A: Check storage class exists**
```powershell
kubectl get storageclass
# If missing, apply appropriate storage class for your provider
```

**Option B: Verify storage provisioner is running**
```powershell
kubectl get pods -n kube-system | grep ebs
```

**Option C: Delete and recreate PVC**
```powershell
kubectl delete pvc -n default <pvc-name>
# Wait for automatic recreation or manually reapply
```

#### Prevention

- Verify storage class is available before deployment
- Use appropriate storage class for workload type
- Monitor storage usage proactively

---

## General Troubleshooting Commands

### Useful diagnostic commands

```powershell
# View all alerts currently firing
kubectl get alertmanager -n monitoring
kubectl get alerts -A

# Check Prometheus scrape targets
kubectl port-forward -n monitoring svc/kube-prom-stack-kube-prome-prometheus 9090:9090
# Visit http://localhost:9090/targets

# Check Alertmanager configuration
kubectl get alertmanager -n monitoring -o yaml

# View pod logs with context
kubectl logs -n default <pod-name> --timestamps=true --tail=200

# Check resource quotas
kubectl describe resourcequota -n default

# Monitor cluster events
kubectl get events -A --sort-by='.lastTimestamp' -w
```

### Escalation Path

1. **Warning alerts:** Check logs, verify configuration, attempt restart
2. **Critical alerts:** Page on-call engineer, prepare rollback plan
3. **Persistent issues:** Open ticket, investigate root cause, implement prevention

---

## Contact & Escalation

- **On-Call Engineer:** Check PagerDuty/Slack for current rotation
- **Incident Commander:** Coordinate response for critical alerts
- **Development Team:** For application-level issues requiring code fixes

---

## Related Documentation

- [Architecture Overview](./architecture.md)
- [Service API Documentation](./EVENT_SERVICE_API_DOCUMENTATION.md)
- [Deployment Guide](./deployment/eks-deployment-guide.md)
- [Event Service Testing Guide](./EVENT_SERVICE_TESTING_GUIDE.md)
