locals {

  # instead of https://raw.githubusercontent.com/hetznercloud/hcloud-cloud-controller-manager/master/deploy/ccm.yaml
  # need to add HCLOUD_NETWORK and co. env vars for LB internal IP support
  # https://github.com/hetznercloud/hcloud-cloud-controller-manager/blob/master/hcloud/cloud.go#L33
  # https://github.com/hetznercloud/hcloud-cloud-controller-manager/blob/master/internal/hcops/load_balancer.go#L506
  hcloud_ccm_yaml = <<-EOF
    apiVersion: v1
    kind: ServiceAccount
    metadata:
      name: cloud-controller-manager
      namespace: kube-system
    ---
    kind: ClusterRoleBinding
    apiVersion: rbac.authorization.k8s.io/v1
    metadata:
      name: system:cloud-controller-manager
    roleRef:
      apiGroup: rbac.authorization.k8s.io
      kind: ClusterRole
      name: cluster-admin
    subjects:
      - kind: ServiceAccount
        name: cloud-controller-manager
        namespace: kube-system
    ---
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: hcloud-cloud-controller-manager
      namespace: kube-system
    spec:
      replicas: 1
      revisionHistoryLimit: 2
      selector:
        matchLabels:
          app: hcloud-cloud-controller-manager
      template:
        metadata:
          labels:
            app: hcloud-cloud-controller-manager
          annotations:
            scheduler.alpha.kubernetes.io/critical-pod: ''
        spec:
          serviceAccountName: cloud-controller-manager
          dnsPolicy: Default
          tolerations:
            # this taint is set by all kubelets running `--cloud-provider=external`
            # so we should tolerate it to schedule the cloud controller manager
            - key: "node.cloudprovider.kubernetes.io/uninitialized"
              value: "true"
              effect: "NoSchedule"
            - key: "CriticalAddonsOnly"
              operator: "Exists"
            # cloud controller managers should be able to run on masters
            - key: "node-role.kubernetes.io/master"
              effect: NoSchedule
            - key: "node.kubernetes.io/not-ready"
              effect: "NoSchedule"
          containers:
            - image: hetznercloud/hcloud-cloud-controller-manager:${var.hcloud_ccm_version}
              name: hcloud-cloud-controller-manager
              command:
                - "/bin/hcloud-cloud-controller-manager"
                - "--cloud-provider=hcloud"
                - "--leader-elect=false"
                - "--allow-untagged-cloud"
              resources:
                requests:
                  cpu: 100m
                  memory: 50Mi
              env:
                - name: NODE_NAME
                  valueFrom:
                    fieldRef:
                      fieldPath: spec.nodeName
                - name: HCLOUD_TOKEN
                  valueFrom:
                    secretKeyRef:
                      name: hcloud
                      key: token
                - name: HCLOUD_NETWORK
                  valueFrom:
                    secretKeyRef:
                      name: hcloud
                      key: network
                - name: HCLOUD_LOAD_BALANCERS_LOCATION
                  valueFrom:
                    secretKeyRef:
                      name: hcloud
                      key: lb_location
                - name: HCLOUD_LOAD_BALANCERS_USE_PRIVATE_IP
                  valueFrom:
                    secretKeyRef:
                      name: hcloud
                      key: lb_use_private_ip
                - name: HCLOUD_LOAD_BALANCERS_DISABLE_IPV6
                  valueFrom:
                    secretKeyRef:
                      name: hcloud
                      key: lb_disable_ipv6
                - name: HCLOUD_LOAD_BALANCERS_DISABLE_PRIVATE_INGRESS
                  valueFrom:
                    secretKeyRef:
                      name: hcloud
                      key: lb_disable_private_ingress
                - name: HCLOUD_DEBUG
                  valueFrom:
                    secretKeyRef:
                      name: hcloud
                      key: debug
EOF
}
