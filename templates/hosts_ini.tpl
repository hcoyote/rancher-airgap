[leaders]
%{ for i, ip in leader_public_ips ~}
${ ip } ansible_user=${ ssh_user } ansible_become=True private_ip=${leader_private_ips[i]}
%{ endfor ~}

[workers]
%{ for i, ip in worker_public_ips ~}
${ ip } ansible_user=${ ssh_user } ansible_become=True private_ip=${worker_private_ips[i]}
%{ endfor ~}


[k8s_cluster:children]
leaders
workers
