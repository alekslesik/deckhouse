# deckhouse
deckhouse


kubectl create secret docker-registry digit-dgepu-secret \
  --docker-server=http://85.141.97.224:443 \
  --docker-username=admin \
  --docker-password=Metrolog1 \
  --docker-email=alekslesik@gmail.com
  
  
  watch -n 1 "kubectl get po -o wide | grep -E 'digit-cassandra-deployment|digit-cassandra-statefulset|digit-dgepu-deployment|digit-postgres-deployment|digit-svd-simple-deployment' | sed 's/-[a-z0-9]*$//' | uniq"

watch -c kubectl exec -n d8-sds-replicated-volume deploy/linstor-controller -- linstor r l

awk '$1" "$2 >= "2024-12-10 09:25:00.000" && $1" "$2 <= "2024-12-10 09:37:00.000"' app.log > log.log
kubectl cp digit-dgepu-deployment-744bdfbc6-k85g5:opt/app_home/logs/log.log ./log.log
tar -czf log.tar.gz log.log

# Restore
kubectl -n digit cp /root/backup/meas_params.backup digit-postgres-deployment-fc6f77bb6-wz9cg:/var/lib/postgresql/data/meas_params.backup;
kubectl  -n digit exec -it digit-postgres-deployment-fc6f77bb6-wz9cg -- /bin/bash -c "pg_restore -U postgres -d meas_params /var/lib/postgresql/data/meas_params.backup";
kubectl  -n digit cp /root/backup/meas_params.backup digit-postgres-deployment-fc6f77bb6-wz9cg:/var/lib/postgresql/data/pros.backup;
kubectl  -n digitl exec -it digit-postgres-deployment-fc6f77bb6-wz9cg -- /bin/bash -c "pg_restore -U postgres -d pros /var/lib/postgresql/data/pros.backup";

# Dump
kubectl exec -it digit-postgres-deployment-fc6f77bb6-wz9cg -- /bin/bash -c "pg_dump -U postgres -Fc meas_params > /var/lib/postgresql/data/meas_params.backup";
kubectl cp digit-postgres-deployment-fc6f77bb6-wz9cg:/var/lib/postgresql/data/meas_params.backup /home/zyfra/backup/meas_params.backup;
kubectl exec -it digit-postgres-deployment-fc6f77bb6-wz9cg -- /bin/bash -c "pg_dump -U postgres -Fc pros > /var/lib/postgresql/data/pros.backup";
kubectl cp digit-postgres-deployment-fc6f77bb6-wz9cg:/var/lib/postgresql/data/pros.backup /home/zyfra/backup/pros.backup;


vlSLTvazSgVE6fhP


glpat-DN9RyT3iWHai23bovTBx


kubectl patch DeckhouseRelease ВЕРСИЯ_РЕЛИЗА --type=merge -p='{"approved": true}'


kubectl -n d8-system exec -it $(kubectl -n d8-system get leases.coordination.k8s.io deckhouse-leader-election -o jsonpath='{.spec.holderIdentity}' | awk -F'.' '{ print $1 }') -c deckhouse -- deckhouse-controller queue list


kubectl create secret docker-registry digit-dgepu-secret \
  --docker-server=http://85.141.97.224:443 \
  --docker-username=admin \
  --docker-password=Metrolog1 \
  --docker-email=alekslesik@gmail.com


echo "Test UDP packet" | nc -u digit-svd-control-service.default.svc.cluster.local 11000


apiVersion: deckhouse.io/v1alpha1
kind: ModuleConfig
metadata:
  annotations:
    kubectl.kubernetes.io/last-applied-configuration: |
      {"apiVersion":"deckhouse.io/v1alpha1","kind":"ModuleConfig","metadata":{"annotations":{},"name":"metallb"},"spec":{"enabled":true,"settings":{"addressPools":[{"addresses":["172.21.100.25/24"],"name":"frontend-pool","protocol":"layer2"}],"speaker":{"nodeSelector":{"node-role.kubernetes.io/control-plane":""}}},"version":1}}
  creationTimestamp: "2024-07-25T07:42:21Z"
  generation: 8
  name: metallb
  resourceVersion: "27197268"
  uid: c48805f5-224f-47d7-9a1a-71427f3a32bf
spec:
  enabled: true
  settings:
    addressPools:
    - addresses:
      - 172.21.100.25/32
      name: frontend-pool
      protocol: layer2
    speaker:
      nodeSelector:
        node-role.kubernetes.io/control-plane: ""
  version: 1
status:
  message: ""
  version: "1"

