[leaders]
%{ for i, ip in leader_public_ips ~}
${ ip } ansible_user=${ ssh_user } ansible_become=True private_ip=${leader_private_ips[i]} rke2_type=server
%{ endfor ~}

[workers]
%{ for i, ip in worker_public_ips ~}
${ ip } ansible_user=${ ssh_user } ansible_become=True private_ip=${worker_private_ips[i]} rke2_type=agent
%{ endfor ~}

[proxy]
%{ for i, ip in proxy_public_ips ~}
${ ip } ansible_user=${ ssh_user } ansible_become=True private_ip=${proxy_private_ips[i]}
%{ endfor ~}

[k8s_cluster:children]
leaders
workers
