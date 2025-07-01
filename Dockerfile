ARG RHEL_VERSION
FROM rockylinux/rockylinux:${RHEL_VERSION}

ARG RHEL_VERSION
ARG PG_VERSION
ARG PG_HINT_PLAN_VERSION

ENV PATH /usr/pgsql-${PG_VERSION}/bin:$PATH
ENV PGDATA /var/lib/pgsql/${PG_VERSION}/data


################################################################################
#
# Prerequisite
#
################################################################################

# Install packages for build
RUN dnf update -y
RUN dnf install -y clang gcc git flex make rpmdevtools

# Install PostgreSQL
RUN if [ "${RHEL_VERSION}" = "8" ]; then \
        dnf install -y --enablerepo=powertools perl-IPC-Run; \
    else \
        dnf install -y --enablerepo=crb perl-IPC-Run; \
    fi
RUN dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-${RHEL_VERSION}-x86_64/pgdg-redhat-repo-latest.noarch.rpm
RUN if [ "${RHEL_VERSION}" = "8" || "${RHEL_VERSION}" = "9" ]; then \
        dnf -qy module disable postgresql; \
    fi

# If you install the beta version, you need to enable pgdg${PG_VERSION}-updates-testing
RUN if [ "${PG_VERSION}" = "18" ]; then \
        dnf install -y --enablerepo=pgdg${PG_VERSION}-updates-testing \
            postgresql${PG_VERSION}-server \
            postgresql${PG_VERSION}-devel \
            postgresql${PG_VERSION}-llvmjit \
            postgresql${PG_VERSION}-contrib; \
    else \
        dnf install -y \
            postgresql${PG_VERSION}-server \
            postgresql${PG_VERSION}-devel \
            postgresql${PG_VERSION}-llvmjit \
            postgresql${PG_VERSION}-contrib; \
    fi


################################################################################
#
# Build RPMs
#
################################################################################

# Build by postgres user
USER postgres
WORKDIR /var/lib/pgsql/

RUN rpmdev-setuptree
RUN git clone https://github.com/ossc-db/pg_hint_plan.git
RUN cd pg_hint_plan && \
    git switch PG${PG_VERSION} && \
    git archive HEAD \
        --format=tar.gz \
        --prefix=pg_hint_plan${PG_VERSION}-${PG_HINT_PLAN_VERSION}/ \
        --output=../rpmbuild/SOURCES/pg_hint_plan${PG_VERSION}-${PG_HINT_PLAN_VERSION}.tar.gz
RUN cp -a pg_hint_plan/SPECS/pg_hint_plan${PG_VERSION}.spec rpmbuild/SPECS

RUN if [ "${PG_VERSION}" = "13" ]; then \
        QA_RPATHS=0x0002 rpmbuild rpmbuild/SPECS/pg_hint_plan${PG_VERSION}.spec \
            -bb --define="dist .pg${PG_VERSION}.rhel${RHEL_VERSION}"; \
    else \
        rpmbuild rpmbuild/SPECS/pg_hint_plan${PG_VERSION}.spec \
            -bb --define="dist .pg${PG_VERSION}.rhel${RHEL_VERSION}"; \
    fi


################################################################################
#
# Run regression tests
#
################################################################################

USER root
RUN rpm -ivh /var/lib/pgsql/rpmbuild/RPMS/x86_64/*

USER postgres
RUN initdb --no-locale -E UTF8
RUN echo "shared_preload_libraries = 'pg_stat_statements'" >> ${PGDATA}/postgresql.conf
RUN pg_ctl -w start
RUN make -C pg_hint_plan installcheck; exit 0
RUN cat /var/lib/pgsql/pg_hint_plan/regression.diffs
